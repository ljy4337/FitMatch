-- MANUAL rollback candidate for 127_zara_retailer_api_v2_Apply.sql.
-- Replaces TWO existing functions. No new table/RPC/schema and no data cleanup.
-- Historical product/user rows and the old input path remain unchanged.
-- Restores the exact deployed r1 function bodies/checksums. It does not rewrite
-- products, receipts, overrides, or any user-owned row.
-- Apply failure rolls back atomically. Do not bypass preconditions.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $pre$ DECLARE g record;p record; BEGIN
 FOR g IN SELECT * FROM jsonb_to_recordset($guards$[{"signature":"fitmatch_vnext.classification_decision(text,text)","old_md5":"5a81fa24b06a3aa43f7a9ffab553788a","new_md5":"56e82046a4f6d0a279f16eb1f34da992","acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres,anon=X/postgres}","owner":"postgres","definer":false},{"signature":"fitmatch_vnext.classification_recovery_options(uuid)","old_md5":"dca1dda221090e661628ffb5811e13ef","new_md5":"d8a1a17c94d33b1a9d5170ab4270e7f1","acl":"{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}","owner":"postgres","definer":true},{"signature":"fitmatch_vnext.classification_tuple_validation(text,text,text,text,text,text)","old_md5":"0fd70e628ad9634cd126b3fef191d570","new_md5":"0fd70e628ad9634cd126b3fef191d570","acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","owner":"postgres","definer":false},{"signature":"fitmatch_vnext.effective_target_classification(uuid)","old_md5":"f7f80c4f87c99fff9a645842ee6d5c4a","new_md5":"f7f80c4f87c99fff9a645842ee6d5c4a","acl":"{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}","owner":"postgres","definer":true},{"signature":"fitmatch_vnext.ingest_product_observation_v2(jsonb,uuid)","old_md5":"3d0e80ec9669a829eae70f4fb431f86e","new_md5":"3d0e80ec9669a829eae70f4fb431f86e","acl":"{postgres=X/postgres,service_role=X/postgres}","owner":"postgres","definer":true},{"signature":"fitmatch_vnext.resolve_product_classification(text,text,boolean)","old_md5":"4256c599056b98ddc10a25f532562484","new_md5":"4256c599056b98ddc10a25f532562484","acl":"{postgres=X/postgres,service_role=X/postgres}","owner":"postgres","definer":true},{"signature":"fitmatch_vnext.set_user_product_classification(uuid,text,text,text,text,uuid,integer)","old_md5":"5cc123c89ca7c17154d259791f5f7a1f","new_md5":"5cc123c89ca7c17154d259791f5f7a1f","acl":"{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}","owner":"postgres","definer":true}]$guards$::jsonb)
  AS x(signature text,old_md5 text,new_md5 text,acl text,owner text,definer boolean) LOOP
  SELECT prosrc,proacl,proowner,prosecdef INTO p FROM pg_proc WHERE oid=to_regprocedure(g.signature);
  IF NOT FOUND THEN RAISE EXCEPTION 'FM_PROVIDER_MISSING_FUNCTION: %',g.signature; END IF;
  IF md5(replace(p.prosrc,chr(13),'')) NOT IN (g.old_md5,g.new_md5)
    OR p.proacl::text IS DISTINCT FROM g.acl OR pg_get_userbyid(p.proowner) IS DISTINCT FROM g.owner
    OR p.prosecdef IS DISTINCT FROM g.definer
  THEN RAISE EXCEPTION 'FM_PROVIDER_BASELINE_DRIFT: %',g.signature; END IF;
 END LOOP;
END $pre$;
CREATE OR REPLACE FUNCTION fitmatch_vnext.classification_decision(p_source_code text, p_source_product_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
 base jsonb; product_row fitmatch_vnext.products%rowtype;
 p_observation jsonb; fact_array jsonb; envelope jsonb; facts_result jsonb;
 policy_value constant jsonb := $policy${"version":"fitmatch-evidence-policy-2026-v2","rules":[{"rule_id":"scope.upper","dimension":"garment_type_code","values":["sleeveless_tshirt","tshirt","tank_top","sweatshirt","knit_sweater","shirt_blouse","polo_shirt","hoodie","cardigan","knit_vest","base_layer_top","sports_top","bodysuit_top","zip_hoodie","homewear_top"],"pattern":"^(상의|TOPS)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"scope.pants","dimension":"garment_type_code","values":["denim_pants","slacks_trousers","chino_cotton_pants","cargo_pants","casual_pants","shorts","sweat_jogger_pants","other_standard_pants","leggings","homewear_bottom"],"pattern":"^(바지|팬츠|하의|기타 바지|PANTS|TROUSERS|PANTALON)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"scope.inner","dimension":"garment_type_code","values":["base_layer_top","men_undershirt","women_camisole","women_bra","men_briefs","men_trunks","women_panty","women_slip"],"pattern":"^(이너웨어|언더웨어|UNDERWEAR|INNERWEAR|INNER TOPS|이너웨어 상의)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.tshirt","dimension":"garment_type_code","values":["tshirt"],"pattern":"(티셔츠|반팔티|긴팔티|그래픽T|크루넥T|U넥T|V넥T|\\mtee\\M|\\mt[ -]?shirt[s]?\\M)","fields":["category","name"],"unless_pattern":"(폴로|카라|니트|KNIT|민소매|슬리브리스|sleeveless|원피스|dress|셔츠\\s*&|후리스)","context":"OUTER_CONTEXT"},{"rule_id":"type.base_layer","dimension":"garment_type_code","values":["base_layer_top"],"pattern":"(티셔츠|크루넥T|U넥T|V넥T|이너웨어 상의|INNER TOPS|undershirt|base.layer top)","fields":["category","name"],"unless_pattern":"(원피스|드레스)","context":"INNER_CONTEXT"},{"rule_id":"type.sleeveless_tee","dimension":"garment_type_code","values":["sleeveless_tshirt"],"pattern":"(민소매 티셔츠|슬리브리스 티셔츠|sleeveless t.shirt)","fields":["category","name"],"unless_pattern":"(원피스|dress)","context":"OUTER_CONTEXT"},{"rule_id":"type.tank","dimension":"garment_type_code","values":["tank_top"],"pattern":"(탱크[톱탑]|tank top|싱글렛|singlet)","fields":["category","name"],"unless_pattern":"(원피스|dress)","context":"OUTER_CONTEXT"},{"rule_id":"type.shirt.name","dimension":"garment_type_code","values":["shirt_blouse"],"pattern":"(셔츠|블라우스|\\mshirts?\\M|\\mblouses?\\M)","fields":["name"],"unless_pattern":"(티셔츠|폴로|카라|스웨트[ ]?셔츠|맨투맨|t.shirt|sweatshirt|polo|원피스|dress|오버셔츠|overshirt|파자마|이너웨어|셔츠\\s*&|후리스)","context":"ANY"},{"rule_id":"type.shirt.category","dimension":"garment_type_code","values":["shirt_blouse"],"pattern":"(셔츠|블라우스|\\mshirts?\\M|\\mblouses?\\M)","fields":["category"],"unless_pattern":"(티셔츠|폴로|카라|스웨트[ ]?셔츠|맨투맨|t.shirt|sweatshirt|polo|원피스|dress|오버셔츠|overshirt|파자마|이너웨어|셔츠\\s*&|후리스)|^셔츠$","context":"ANY"},{"rule_id":"type.polo","dimension":"garment_type_code","values":["polo_shirt"],"pattern":"(폴로셔츠|카라[ ]?티|피케.?티셔츠|\\mpolo\\M)","fields":["category","name"],"unless_pattern":"(니트|knit|원피스|dress)","context":"ANY"},{"rule_id":"type.knit","dimension":"garment_type_code","values":["knit_sweater"],"pattern":"(니트|스웨터|\\mknit\\M|sweater|jumper)","fields":["category","name"],"unless_pattern":"(가디건|카디건|cardigan|베스트|vest|원피스|dress|팬츠|pants|스커트|skirt|가디건\\s*&|니트\\s*/|스웨터\\s*\\|)","context":"ANY"},{"rule_id":"type.cardigan","dimension":"garment_type_code","values":["cardigan"],"pattern":"(가디건|카디건|cardigan)","fields":["category","name"],"unless_pattern":"(니트 & 가디건|스웨터.*\\||sweaters? \\|)","context":"ANY"},{"rule_id":"type.knit_vest","dimension":"garment_type_code","values":["knit_vest"],"pattern":"(니트[ ]?베스트|knit vest)","fields":["category","name"],"unless_pattern":"(원피스|dress)","context":"ANY"},{"rule_id":"type.sweatshirt","dimension":"garment_type_code","values":["sweatshirt"],"pattern":"(맨투맨|스웨트[ ]?셔츠|sweatshirt)","fields":["category","name"],"unless_pattern":"(후드|hood|후리스|스웨트셔츠\\s*&|스웨트셔츠\\s*\\|)","context":"ANY"},{"rule_id":"type.hoodie","dimension":"garment_type_code","values":["hoodie"],"pattern":"(후드[ ]?티|후드티셔츠|\\mhoodie\\M)","fields":["category","name"],"unless_pattern":"(집업|zip|재킷|자켓|jacket|바람막이)","context":"ANY"},{"rule_id":"type.zip_hoodie","dimension":"garment_type_code","values":["zip_hoodie"],"pattern":"(후드[ ]?집업|스웨트풀집|zip.up hoodie)","fields":["category","name"],"unless_pattern":"(후리스|fleece|바람막이)","context":"ANY"},{"rule_id":"type.denim","dimension":"garment_type_code","values":["denim_pants"],"pattern":"(데님[ ]?팬츠|청바지|청/데님 팬츠|\\mjeans\\M|denim pants)","fields":["category","name"],"unless_pattern":"(재킷|셔츠|스커트|jacket|shirt|skirt)","context":"ANY"},{"rule_id":"type.slacks","dimension":"garment_type_code","values":["slacks_trousers"],"pattern":"(슬랙스|\\mslacks\\M|sastrería pant|tailored trousers)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.chino","dimension":"garment_type_code","values":["chino_cotton_pants"],"pattern":"(치노|코튼 팬츠|chino)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.cargo","dimension":"garment_type_code","values":["cargo_pants"],"pattern":"(카고|유틸리티팬츠|cargo|utility pants|crg pnt)","fields":["category","name"],"unless_pattern":"(재킷|jacket)","context":"ANY"},{"rule_id":"type.jogger","dimension":"garment_type_code","values":["sweat_jogger_pants"],"pattern":"(조거[ ]?팬츠|스웨트[ ]?팬츠|트레이닝[ /]?조거 팬츠|jogger|sweatpants)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.shorts","dimension":"garment_type_code","values":["shorts"],"pattern":"(반바지|쇼트팬츠|쇼트 팬츠|숏[ ]?팬츠|쇼츠|버뮤다|\\mshorts\\M|bermuda)","fields":["category","name"],"unless_pattern":"(데님|청바지|denim|카고|cargo|코튼저지|팬티|brief|trunk)","context":"OUTER_CONTEXT"},{"rule_id":"type.leggings","dimension":"garment_type_code","values":["leggings"],"pattern":"(레깅스|leggings)","fields":["category","name"],"unless_pattern":"(레깅스 & 팬츠)","context":"ANY"},{"rule_id":"type.skirt","dimension":"garment_type_code","values":["skirt"],"pattern":"(스커트|치마|\\mskirt[s]?\\M)","fields":["category","name"],"unless_pattern":"(원피스.*스커트|스커트.*원피스|원피스|스커트 팬츠)","context":"ANY"},{"rule_id":"type.dress","dimension":"garment_type_code","values":["dress"],"pattern":"(원피스|드레스|\\mdresses?\\M|\\mdress\\M)","fields":["category","name"],"unless_pattern":"(원피스.*스커트|스커트.*원피스)","context":"ANY"},{"rule_id":"type.blazer","dimension":"garment_type_code","values":["blazer"],"pattern":"(블레이저|브레이저|blazer)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.trench","dimension":"garment_type_code","values":["trench_coat"],"pattern":"(트렌치[ ]?코트|trench coat)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.coat","dimension":"garment_type_code","values":["coat"],"pattern":"(코트|\\mcoat\\M)","fields":["category","name"],"unless_pattern":"(트렌치|trench|재킷 & 코트)","context":"ANY"},{"rule_id":"type.ma1","dimension":"garment_type_code","values":["ma1"],"pattern":"(MA-1|항공점퍼)","fields":["category","name"],"unless_pattern":"(블루종/MA-1)","context":"ANY"},{"rule_id":"type.blouson","dimension":"garment_type_code","values":["blouson"],"pattern":"(블루종|blouson)","fields":["category","name"],"unless_pattern":"(블루종/MA-1|파카 & 블루종)","context":"ANY"},{"rule_id":"type.windbreaker","dimension":"garment_type_code","values":["windbreaker"],"pattern":"(바람막이|windbreaker)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.anorak","dimension":"garment_type_code","values":["anorak"],"pattern":"(아노락|anorak)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.fleece","dimension":"garment_type_code","values":["fleece_jacket"],"pattern":"(플리스[ ]?재킷|후리스[ ]?재킷|fleece jacket)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.puffer","dimension":"garment_type_code","values":["puffer_jacket"],"pattern":"(다운[ ]?재킷|패딩[ ]?재킷|다운[ ]?자켓|puffer jacket)","fields":["category","name"],"unless_pattern":"(조끼|vest)","context":"ANY"},{"rule_id":"type.puffer_vest","dimension":"garment_type_code","values":["puffer_vest"],"pattern":"(패딩[ ]?조끼|다운[ ]?베스트|puffer vest)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.mouton","dimension":"garment_type_code","values":["mouton"],"pattern":"(무스탕|mouton)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.bra","dimension":"garment_type_code","values":["women_bra"],"pattern":"^(브라|와이어리스 브라)$","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.briefs","dimension":"garment_type_code","values":["men_briefs"],"pattern":"(복서브리프|boxer briefs)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.trunks","dimension":"garment_type_code","values":["men_trunks"],"pattern":"(트렁크|trunks)","fields":["category","name"],"unless_pattern":"","context":"INNER_CONTEXT"},{"rule_id":"type.panty","dimension":"garment_type_code","values":["women_panty"],"pattern":"(여성 팬티|women.s panties)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.camisole","dimension":"garment_type_code","values":["women_camisole"],"pattern":"(캐미솔|camisole)","fields":["category","name"],"unless_pattern":"(원피스|dress)","context":"INNER_CONTEXT"},{"rule_id":"scope.shirt_family","dimension":"garment_type_code","values":["shirt_blouse","polo_shirt"],"pattern":"^셔츠$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"scope.vest","dimension":"garment_type_code","values":["outer_vest","knit_vest","puffer_vest"],"pattern":"^(조끼|베스트)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.structured_knit_vest","dimension":"garment_type_code","values":["knit_vest"],"pattern":"^KNIT VEST$","fields":["subfamily"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.structured_knit_sweater","dimension":"garment_type_code","values":["knit_sweater"],"pattern":"^KNIT SWEATER$","fields":["subfamily"],"unless_pattern":"","context":"ANY"},{"rule_id":"scope.jacket","dimension":"garment_type_code","values":["jacket","blouson","blazer","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","mouton"],"pattern":"(재킷|자켓|\\mjacket\\M|F. Cazadora)","fields":["category","name"],"unless_pattern":"(재킷 &|나일론/코치|점퍼/재킷)","context":"ANY"},{"rule_id":"unsupported.jumpsuit","dimension":"unsupported_type","values":["jumpsuit"],"pattern":"(점프수트|jumpsuit)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"unsupported.skorts","dimension":"unsupported_type","values":["skorts"],"pattern":"(스코츠|스커트 팬츠|\\mskorts?\\M)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"exclude.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^(가방|모자|벨트|선글라스|우산|장갑|신발|슈즈|향수|액세서리|BAG|SHOES|PERFUME|ACCESSORIES|BAGS)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"exclude.upper_lower_set","dimension":"exclusion","values":["UPPER_LOWER_SET"],"pattern":"(상[ ]?하의[ ]?세트|상의.*하의.*세트|셔츠.*팬츠.*세트|top and (pants|trousers) set)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"structure.set_ambiguous","dimension":"structure","values":["AMBIGUOUS_BUNDLE"],"pattern":"(세트|\\mset\\M)","fields":["name"],"unless_pattern":"(셋업|set.up|세트.*별도|별도.*세트)","context":"ANY"},{"rule_id":"structure.multipack","dimension":"structure","values":["MULTIPACK"],"pattern":"([2-9][ ]?(팩|P\\M)|multipack|[2-9].pack)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.name.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"(반팔|반소매|쇼트 슬리브|short[ -]sleeve)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.desc.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"(반팔|반소매|쇼트 슬리브|short[ -]sleeve)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"sleeve.name.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"(긴팔|긴소매|롱 슬리브|long[ -]sleeve)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.desc.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"(긴팔|긴소매|롱 슬리브|long[ -]sleeve)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"sleeve.name.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"(민소매|슬리브리스|sleeveless|탱크[탑톱]|캐미솔)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.desc.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"(민소매|슬리브리스|sleeveless|탱크[탑톱]|캐미솔)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"sleeve.name.three_quarter_sleeve","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"(7부[ ]?소매|three.quarter[ -]sleeve)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.desc.three_quarter_sleeve","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"(7부[ ]?소매|three.quarter[ -]sleeve)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"sleeve.category.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"^(반팔|반소매|반소매 티셔츠|short sleeve)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.category.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"^(긴팔|긴소매|긴소매 티셔츠|long sleeve)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.category.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"^(슬리브리스|민소매 티셔츠|캐미솔|탱크탑)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.attribute.short","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"^sleeve=short$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.attribute.long","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"^sleeve=long$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.attribute.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"^sleeve=sleeveless$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.attribute.three-quarter","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"^sleeve=three-quarter$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.short_length","dimension":"lower_length_code","values":["short_length"],"pattern":"(반바지|쇼트팬츠|쇼트 팬츠|숏[ ]?팬츠|쇼츠|버뮤다|\\mshorts\\M|bermuda)","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.cropped_length","dimension":"lower_length_code","values":["cropped_length"],"pattern":"(크롭[ ]?(팬츠|진)|cropped (pants|jeans|trousers))","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.ankle_length","dimension":"lower_length_code","values":["ankle_length"],"pattern":"(앵클[ ]?팬츠|ankle.length)","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.long_length","dimension":"lower_length_code","values":["long_length"],"pattern":"(롱[ ]?팬츠|긴바지|full.length|long trousers|long pants)","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.three_quarter_length","dimension":"lower_length_code","values":["three_quarter_length"],"pattern":"(7부[ ]?(팬츠|바지)|three.quarter trousers)","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"body.short_body","dimension":"body_length_code","values":["short_body"],"pattern":"(미니( [^ .]+){0,3}[ ]?(원피스|스커트)|mini (dress|skirt)|숏[ ]?(코트|패딩))","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"body.description.short_body","dimension":"body_length_code","values":["short_body"],"pattern":"(미니( [^ .]+){0,3}[ ]?(원피스|스커트)|mini (dress|skirt)|숏[ ]?(코트|패딩))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"body.medium_body","dimension":"body_length_code","values":["medium_body"],"pattern":"(미디( [^ .]+){0,3}[ ]?(원피스|스커트)|midi (dress|skirt))","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"body.description.medium_body","dimension":"body_length_code","values":["medium_body"],"pattern":"(미디( [^ .]+){0,3}[ ]?(원피스|스커트)|midi (dress|skirt))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"body.long_body","dimension":"body_length_code","values":["long_body"],"pattern":"(롱[ ]?(원피스|스커트|코트)|맥시[ ]?(원피스|스커트)|long (dress|skirt|coat)|maxi (dress|skirt))","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"body.description.long_body","dimension":"body_length_code","values":["long_body"],"pattern":"(롱[ ]?(원피스|스커트|코트)|맥시[ ]?(원피스|스커트)|long (dress|skirt|coat)|maxi (dress|skirt))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"lower.attribute.long","dimension":"lower_length_code","values":["long_length"],"pattern":"^pant-length=long$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.attribute.short","dimension":"lower_length_code","values":["short_length"],"pattern":"^pant-length=short$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.attribute.ankle","dimension":"lower_length_code","values":["ankle_length"],"pattern":"^pant-length=ankle$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.attribute.cropped","dimension":"lower_length_code","values":["cropped_length"],"pattern":"^pant-length=cropped$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.attribute.three-quarter","dimension":"lower_length_code","values":["three_quarter_length"],"pattern":"^pant-length=three-quarter$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.short_length.description","dimension":"lower_length_code","values":["short_length"],"pattern":"(반바지|쇼트팬츠|쇼트 팬츠|숏[ ]?팬츠|쇼츠|버뮤다|\\mshorts\\M|bermuda)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"lower.cropped_length.description","dimension":"lower_length_code","values":["cropped_length"],"pattern":"(크롭[ ]?(팬츠|진)|cropped (pants|jeans|trousers))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"lower.ankle_length.description","dimension":"lower_length_code","values":["ankle_length"],"pattern":"(앵클[ ]?팬츠|ankle.length)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"lower.long_length.description","dimension":"lower_length_code","values":["long_length"],"pattern":"(롱[ ]?팬츠|긴바지|full.length|long trousers|long pants)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"lower.three_quarter_length.description","dimension":"lower_length_code","values":["three_quarter_length"],"pattern":"(7부[ ]?(팬츠|바지)|three.quarter trousers)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY"}]}$policy$::jsonb;
 version_value constant text := 'fitmatch-vnext-current-retailer-facts-20260909-v2';
 status_value text; reason_value text; candidate_values jsonb := '[]'::jsonb;
 tuple_value jsonb; fixed_value jsonb; unknown_value jsonb;
 conflict boolean := false; product_specific boolean := false; invalid_evidence boolean := false;
BEGIN
 -- New raw API contract is interpreted inside this existing procedure.
 -- Inputs without this envelope retain the exact deployed compatibility path.
 IF EXISTS(SELECT 1 FROM fitmatch_vnext.products p
   WHERE p.source_code=p_source_code AND p.source_product_key=p_source_product_key
     AND p.source_extra#>'{structured_facts,retailer_api}' IS NOT NULL) THEN

DECLARE
 base jsonb; product_row fitmatch_vnext.products%rowtype;
 p_observation jsonb; fact_array jsonb; envelope jsonb; facts_result jsonb;
 policy_value constant jsonb := $policy${"version":"fitmatch-provider-api-policy-20260909-r1","rules":[{"rule_id":"type.tshirt","dimension":"garment_type_code","values":["tshirt"],"pattern":"(티셔츠|반팔티|긴팔티|그래픽T|크루넥T|U넥T|V넥T|\\mtee\\M|\\mt[ -]?shirt[s]?\\M)","fields":["name"],"unless_pattern":"(폴로|카라|니트|KNIT|민소매|슬리브리스|sleeveless|원피스|dress|셔츠\\s*&|후리스)","context":"OUTER_CONTEXT","provider":"any"},{"rule_id":"type.base_layer","dimension":"garment_type_code","values":["base_layer_top"],"pattern":"(티셔츠|크루넥T|U넥T|V넥T|이너웨어 상의|INNER TOPS|undershirt|base.layer top)","fields":["name"],"unless_pattern":"(원피스|드레스)","context":"INNER_CONTEXT","provider":"any"},{"rule_id":"type.sleeveless_tee","dimension":"garment_type_code","values":["sleeveless_tshirt"],"pattern":"(민소매 티셔츠|슬리브리스 티셔츠|sleeveless t.shirt)","fields":["name"],"unless_pattern":"(원피스|dress)","context":"OUTER_CONTEXT","provider":"any"},{"rule_id":"type.tank","dimension":"garment_type_code","values":["tank_top"],"pattern":"(탱크[톱탑]|tank top|싱글렛|singlet)","fields":["name"],"unless_pattern":"(원피스|dress)","context":"OUTER_CONTEXT","provider":"any"},{"rule_id":"type.shirt.name","dimension":"garment_type_code","values":["shirt_blouse"],"pattern":"(셔츠|블라우스|\\mshirts?\\M|\\mblouses?\\M)","fields":["name"],"unless_pattern":"(티셔츠|폴로|카라|스웨트[ ]?셔츠|맨투맨|t.shirt|sweatshirt|polo|원피스|dress|오버셔츠|overshirt|파자마|이너웨어|셔츠\\s*&|후리스)","context":"ANY","provider":"any"},{"rule_id":"type.polo","dimension":"garment_type_code","values":["polo_shirt"],"pattern":"(폴로셔츠|카라[ ]?티|피케.?티셔츠|\\mpolo\\M)","fields":["name"],"unless_pattern":"(니트|knit|원피스|dress)","context":"ANY","provider":"any"},{"rule_id":"type.knit","dimension":"garment_type_code","values":["knit_sweater"],"pattern":"(니트|스웨터|\\mknit\\M|sweater|jumper)","fields":["name"],"unless_pattern":"(가디건|카디건|cardigan|베스트|vest|원피스|dress|팬츠|pants|스커트|skirt|가디건\\s*&|니트\\s*/|스웨터\\s*\\|)|padded|padding|down|wind|스웨트|패딩|다운","context":"ANY","provider":"any"},{"rule_id":"type.cardigan","dimension":"garment_type_code","values":["cardigan"],"pattern":"(가디건|카디건|cardigan)","fields":["name"],"unless_pattern":"(니트 & 가디건|스웨터.*\\||sweaters? \\|)","context":"ANY","provider":"any"},{"rule_id":"type.knit_vest","dimension":"garment_type_code","values":["knit_vest"],"pattern":"(니트[ ]?베스트|knit vest)","fields":["name"],"unless_pattern":"(원피스|dress)","context":"ANY","provider":"any"},{"rule_id":"type.sweatshirt","dimension":"garment_type_code","values":["sweatshirt"],"pattern":"(맨투맨|스웨트[ ]?셔츠|sweatshirt)","fields":["name"],"unless_pattern":"(후드|hood|후리스|스웨트셔츠\\s*&|스웨트셔츠\\s*\\|)","context":"ANY","provider":"any"},{"rule_id":"type.hoodie","dimension":"garment_type_code","values":["hoodie"],"pattern":"(후드[ ]?티|후드티셔츠|\\mhoodie\\M)","fields":["name"],"unless_pattern":"(집업|zip|재킷|자켓|jacket|바람막이)","context":"ANY","provider":"any"},{"rule_id":"type.zip_hoodie","dimension":"garment_type_code","values":["zip_hoodie"],"pattern":"(후드[ ]?집업|스웨트풀집|zip.up hoodie)","fields":["name"],"unless_pattern":"(후리스|fleece|바람막이)","context":"ANY","provider":"any"},{"rule_id":"type.denim","dimension":"garment_type_code","values":["denim_pants"],"pattern":"(데님[ ]?팬츠|청바지|청/데님 팬츠|\\mjeans\\M|denim pants)","fields":["name"],"unless_pattern":"(재킷|셔츠|스커트|jacket|shirt|skirt)","context":"ANY","provider":"any"},{"rule_id":"type.slacks","dimension":"garment_type_code","values":["slacks_trousers"],"pattern":"(슬랙스|\\mslacks\\M|sastrería pant|tailored trousers)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.chino","dimension":"garment_type_code","values":["chino_cotton_pants"],"pattern":"(치노|코튼 팬츠|chino)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.cargo","dimension":"garment_type_code","values":["cargo_pants"],"pattern":"(카고|유틸리티팬츠|cargo|utility pants|crg pnt)","fields":["name"],"unless_pattern":"(재킷|jacket)","context":"ANY","provider":"any"},{"rule_id":"type.jogger","dimension":"garment_type_code","values":["sweat_jogger_pants"],"pattern":"(조거[ ]?팬츠|스웨트[ ]?팬츠|트레이닝[ /]?조거 팬츠|jogger|sweatpants)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.shorts","dimension":"garment_type_code","values":["shorts"],"pattern":"(반바지|쇼트팬츠|쇼트 팬츠|숏[ ]?팬츠|쇼츠|버뮤다|\\mshorts\\M|bermuda)","fields":["name"],"unless_pattern":"(데님|청바지|denim|카고|cargo|코튼저지|팬티|brief|trunk)|스웨트|스웻|sweat|조거|jogger","context":"OUTER_CONTEXT","provider":"any"},{"rule_id":"type.leggings","dimension":"garment_type_code","values":["leggings"],"pattern":"(레깅스|leggings)","fields":["name"],"unless_pattern":"(레깅스 & 팬츠)","context":"ANY","provider":"any"},{"rule_id":"type.skirt","dimension":"garment_type_code","values":["skirt"],"pattern":"(스커트|치마|\\mskirt[s]?\\M)","fields":["name"],"unless_pattern":"(원피스.*스커트|스커트.*원피스|원피스|스커트 팬츠)","context":"ANY","provider":"any"},{"rule_id":"type.dress","dimension":"garment_type_code","values":["dress"],"pattern":"(원피스|드레스|\\mdresses?\\M|\\mdress\\M)","fields":["name"],"unless_pattern":"(원피스.*스커트|스커트.*원피스)","context":"ANY","provider":"any"},{"rule_id":"type.blazer","dimension":"garment_type_code","values":["blazer"],"pattern":"(블레이저|브레이저|blazer)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.trench","dimension":"garment_type_code","values":["trench_coat"],"pattern":"(트렌치[ ]?코트|trench coat)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.coat","dimension":"garment_type_code","values":["coat"],"pattern":"(코트|\\mcoat\\M)","fields":["name"],"unless_pattern":"(트렌치|trench|재킷 & 코트)","context":"ANY","provider":"any"},{"rule_id":"type.ma1","dimension":"garment_type_code","values":["ma1"],"pattern":"(MA-1|항공점퍼)","fields":["name"],"unless_pattern":"(블루종/MA-1)","context":"ANY","provider":"any"},{"rule_id":"type.blouson","dimension":"garment_type_code","values":["blouson"],"pattern":"(블루종|blouson)","fields":["name"],"unless_pattern":"(블루종/MA-1|파카 & 블루종)","context":"ANY","provider":"any"},{"rule_id":"type.windbreaker","dimension":"garment_type_code","values":["windbreaker"],"pattern":"(바람막이|windbreaker)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.anorak","dimension":"garment_type_code","values":["anorak"],"pattern":"(아노락|anorak)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.fleece","dimension":"garment_type_code","values":["fleece_jacket"],"pattern":"(플리스[ ]?재킷|후리스[ ]?재킷|fleece jacket)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.puffer","dimension":"garment_type_code","values":["puffer_jacket"],"pattern":"(다운[ ]?재킷|패딩[ ]?재킷|다운[ ]?자켓|puffer jacket)","fields":["name"],"unless_pattern":"(조끼|vest)","context":"ANY","provider":"any"},{"rule_id":"type.puffer_vest","dimension":"garment_type_code","values":["puffer_vest"],"pattern":"(패딩[ ]?조끼|다운[ ]?베스트|puffer vest)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.mouton","dimension":"garment_type_code","values":["mouton"],"pattern":"(무스탕|mouton)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.bra","dimension":"garment_type_code","values":["women_bra"],"pattern":"^(브라|와이어리스 브라)$","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.briefs","dimension":"garment_type_code","values":["men_briefs"],"pattern":"(복서브리프|boxer briefs)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.trunks","dimension":"garment_type_code","values":["men_trunks"],"pattern":"(트렁크|trunks)","fields":["name"],"unless_pattern":"","context":"INNER_CONTEXT","provider":"any"},{"rule_id":"type.panty","dimension":"garment_type_code","values":["women_panty"],"pattern":"(여성 팬티|women.s panties)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"type.camisole","dimension":"garment_type_code","values":["women_camisole"],"pattern":"(캐미솔|camisole)","fields":["name"],"unless_pattern":"(원피스|dress)","context":"INNER_CONTEXT","provider":"any"},{"rule_id":"scope.jacket","dimension":"garment_type_code","values":["jacket","blouson","blazer","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","mouton"],"pattern":"(재킷|자켓|\\mjacket\\M|F. Cazadora)","fields":["name"],"unless_pattern":"(재킷 &|나일론/코치|점퍼/재킷)","context":"ANY","provider":"any"},{"rule_id":"unsupported.jumpsuit","dimension":"unsupported_type","values":["jumpsuit"],"pattern":"(점프수트|jumpsuit)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"unsupported.skorts","dimension":"unsupported_type","values":["skorts"],"pattern":"(스코츠|스커트 팬츠|\\mskorts?\\M)|skirt[ -]pants","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"exclude.upper_lower_set","dimension":"exclusion","values":["UPPER_LOWER_SET"],"pattern":"(상[ ]?하의[ ]?세트|상의.*하의.*세트|셔츠.*팬츠.*세트|top and (pants|trousers) set)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"structure.set_ambiguous","dimension":"structure","values":["AMBIGUOUS_BUNDLE"],"pattern":"(세트|\\mset\\M)","fields":["name"],"unless_pattern":"(셋업|set.up|세트.*별도|별도.*세트)","context":"ANY","provider":"any"},{"rule_id":"structure.multipack","dimension":"structure","values":["MULTIPACK"],"pattern":"([2-9][ ]?(팩|P\\M)|multipack|[2-9].pack)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"sleeve.name.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"(반팔|반소매|쇼트 슬리브|short[ -]sleeve)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"sleeve.desc.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"(반팔|반소매|쇼트 슬리브|short[ -]sleeve)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"sleeve.name.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"(긴팔|긴소매|롱 슬리브|long[ -]sleeve)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"sleeve.desc.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"(긴팔|긴소매|롱 슬리브|long[ -]sleeve)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"sleeve.name.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"(민소매|슬리브리스|sleeveless|탱크[탑톱]|캐미솔)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"sleeve.desc.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"(민소매|슬리브리스|sleeveless|탱크[탑톱]|캐미솔)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"sleeve.name.three_quarter_sleeve","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"(7부[ ]?소매|three.quarter[ -]sleeve)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"sleeve.desc.three_quarter_sleeve","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"(7부[ ]?소매|three.quarter[ -]sleeve)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"sleeve.attribute.short","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"^sleeve=short$","fields":["attribute"],"unless_pattern":"","context":"ANY","provider":"uniqlo"},{"rule_id":"sleeve.attribute.long","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"^sleeve=long$","fields":["attribute"],"unless_pattern":"","context":"ANY","provider":"uniqlo"},{"rule_id":"sleeve.attribute.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"^sleeve=sleeveless$","fields":["attribute"],"unless_pattern":"","context":"ANY","provider":"uniqlo"},{"rule_id":"sleeve.attribute.three-quarter","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"^sleeve=three-quarter$","fields":["attribute"],"unless_pattern":"","context":"ANY","provider":"uniqlo"},{"rule_id":"lower.short_length","dimension":"lower_length_code","values":["short_length"],"pattern":"(반바지|쇼트팬츠|쇼트 팬츠|숏[ ]?팬츠|쇼츠|버뮤다|\\mshorts\\M|bermuda)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"lower.cropped_length","dimension":"lower_length_code","values":["cropped_length"],"pattern":"(크롭[ ]?(팬츠|진)|cropped (pants|jeans|trousers))","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"lower.ankle_length","dimension":"lower_length_code","values":["ankle_length"],"pattern":"(앵클[ ]?팬츠|ankle.length)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"lower.long_length","dimension":"lower_length_code","values":["long_length"],"pattern":"(롱[ ]?팬츠|긴바지|full.length|long trousers|long pants)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"lower.three_quarter_length","dimension":"lower_length_code","values":["three_quarter_length"],"pattern":"(7부[ ]?(팬츠|바지)|three.quarter trousers)","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"body.short_body","dimension":"body_length_code","values":["short_body"],"pattern":"(미니( [^ .]+){0,3}[ ]?(원피스|스커트)|mini (dress|skirt)|숏[ ]?(코트|패딩))","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"body.description.short_body","dimension":"body_length_code","values":["short_body"],"pattern":"(미니( [^ .]+){0,3}[ ]?(원피스|스커트)|mini (dress|skirt)|숏[ ]?(코트|패딩))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"body.medium_body","dimension":"body_length_code","values":["medium_body"],"pattern":"(미디( [^ .]+){0,3}[ ]?(원피스|스커트)|midi (dress|skirt))","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"body.description.medium_body","dimension":"body_length_code","values":["medium_body"],"pattern":"(미디( [^ .]+){0,3}[ ]?(원피스|스커트)|midi (dress|skirt))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"body.long_body","dimension":"body_length_code","values":["long_body"],"pattern":"(롱[ ]?(원피스|스커트|코트)|맥시[ ]?(원피스|스커트)|long (dress|skirt|coat)|maxi (dress|skirt))","fields":["name"],"unless_pattern":"","context":"ANY","provider":"any"},{"rule_id":"body.description.long_body","dimension":"body_length_code","values":["long_body"],"pattern":"(롱[ ]?(원피스|스커트|코트)|맥시[ ]?(원피스|스커트)|long (dress|skirt|coat)|maxi (dress|skirt))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"lower.attribute.long","dimension":"lower_length_code","values":["long_length"],"pattern":"^pant-length=long$","fields":["attribute"],"unless_pattern":"","context":"ANY","provider":"uniqlo"},{"rule_id":"lower.attribute.short","dimension":"lower_length_code","values":["short_length"],"pattern":"^pant-length=short$","fields":["attribute"],"unless_pattern":"","context":"ANY","provider":"uniqlo"},{"rule_id":"lower.attribute.ankle","dimension":"lower_length_code","values":["ankle_length"],"pattern":"^pant-length=ankle$","fields":["attribute"],"unless_pattern":"","context":"ANY","provider":"uniqlo"},{"rule_id":"lower.attribute.cropped","dimension":"lower_length_code","values":["cropped_length"],"pattern":"^pant-length=cropped$","fields":["attribute"],"unless_pattern":"","context":"ANY","provider":"uniqlo"},{"rule_id":"lower.attribute.three-quarter","dimension":"lower_length_code","values":["three_quarter_length"],"pattern":"^pant-length=three-quarter$","fields":["attribute"],"unless_pattern":"","context":"ANY","provider":"uniqlo"},{"rule_id":"lower.short_length.description","dimension":"lower_length_code","values":["short_length"],"pattern":"(반바지|쇼트팬츠|쇼트 팬츠|숏[ ]?팬츠|쇼츠|버뮤다|\\mshorts\\M|bermuda)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"lower.cropped_length.description","dimension":"lower_length_code","values":["cropped_length"],"pattern":"(크롭[ ]?(팬츠|진)|cropped (pants|jeans|trousers))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"lower.ankle_length.description","dimension":"lower_length_code","values":["ankle_length"],"pattern":"(앵클[ ]?팬츠|ankle.length)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"lower.long_length.description","dimension":"lower_length_code","values":["long_length"],"pattern":"(롱[ ]?팬츠|긴바지|full.length|long trousers|long pants)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"lower.three_quarter_length.description","dimension":"lower_length_code","values":["three_quarter_length"],"pattern":"(7부[ ]?(팬츠|바지)|three.quarter trousers)","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아니|아닙|않|처럼|보다|비교|without|pair with|not |스타일로)","context":"ANY","provider":"any"},{"rule_id":"name.sweat_zip","dimension":"garment_type_code","values":["zip_hoodie"],"pattern":"(スウェットフルジップ|스웨트풀집|스웨트.*풀집파카)","fields":["name"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"name.sweatshirt_ko","dimension":"garment_type_code","values":["sweatshirt"],"pattern":"(스웨트셔츠)","fields":["name"],"provider":"any","context":"ANY","unless_pattern":"(후드|집업|파자마)"},{"rule_id":"name.denim_jeans_ko","dimension":"garment_type_code","values":["denim_pants"],"pattern":"(\\m진\\M|레귤러진|슬림진|배기진|와이드진|스트레이트진|핏진)","fields":["name"],"provider":"any","context":"ANY","unless_pattern":"(재킷|셔츠|스커트|지갑)"},{"rule_id":"name.homewear_top","dimension":"garment_type_code","values":["homewear_top"],"pattern":"(파자마[ ]?(셔츠|상의|탑)|pajama[ ]?(shirt|top))","fields":["name"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"name.homewear_bottom","dimension":"garment_type_code","values":["homewear_bottom"],"pattern":"(파자마[ ]?(팬츠|바지|하의)|pajama[ ]?(pants|bottom))","fields":["name"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"name.socks_exclusion","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"(양말|삭스|\\msocks?\\M)","fields":["name"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"name.swimwear_unmapped","dimension":"unsupported_type","values":["swimwear"],"pattern":"(수영복|스윔웨어|비키니|swimsuit|bikini)","fields":["name"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"name.coverall_unmapped","dimension":"unsupported_type","values":["coverall"],"pattern":"(커버올|coverall|ロンパース)","fields":["name"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"name.bodysuit","dimension":"garment_type_code","values":["bodysuit_top"],"pattern":"(바디수트|바디슈트|bodysuit)","fields":["name"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.explicit_t_suffix","dimension":"garment_type_code","values":["tshirt"],"pattern":"[가-힣]T(\\(|\\)|$)","fields":["name"],"provider":"uniqlo","context":"OUTER_CONTEXT","unless_pattern":"(폴로|니트|캐미솔|슬리브리스|민소매|브라)"},{"rule_id":"name.sweat_pants_compound","dimension":"garment_type_code","values":["sweat_jogger_pants"],"pattern":"(스웨트.*팬츠)","fields":["name"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"name.padded_jacket","dimension":"garment_type_code","values":["puffer_jacket"],"pattern":"(down.*jacket|padding jacket|padded jacket|다운.*(패딩|재킷|점퍼))","fields":["name"],"provider":"any","context":"ANY","unless_pattern":"(조끼|베스트|vest)"},{"rule_id":"name.windbreaker_ko","dimension":"garment_type_code","values":["windbreaker"],"pattern":"(윈드브레이커)","fields":["name"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.tops","dimension":"garment_type_code","values":["sleeveless_tshirt","tshirt","tank_top","sweatshirt","knit_sweater","shirt_blouse","polo_shirt","hoodie","cardigan","knit_vest","base_layer_top","sports_top","bodysuit_top","zip_hoodie","homewear_top"],"pattern":"^(tops)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.bottoms","dimension":"garment_type_code","values":["denim_pants","slacks_trousers","chino_cotton_pants","cargo_pants","casual_pants","shorts","sweat_jogger_pants","other_standard_pants","leggings","homewear_bottom"],"pattern":"^(bottoms|pants|wide\\ pants|pants\\ and\\ leggings)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.pants_and_skirts","dimension":"garment_type_code","values":["denim_pants","slacks_trousers","chino_cotton_pants","cargo_pants","casual_pants","shorts","sweat_jogger_pants","other_standard_pants","leggings","skirt"],"pattern":"^(pants\\ and\\ skirts)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.outerwear","dimension":"garment_type_code","values":["jacket","coat","trench_coat","blazer","blouson","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","puffer_vest","outer_vest","mouton"],"pattern":"^(outerwear|jacket|parkas\\ and\\ blousons)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.innerwear","dimension":"garment_type_code","values":["base_layer_top","men_undershirt","women_camisole","women_bra","men_briefs","men_trunks","women_panty","women_slip","leggings"],"pattern":"^(innerwear|underwear|inner\\ tops)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.t_shirts","dimension":"garment_type_code","values":["tshirt","sleeveless_tshirt","tank_top","polo_shirt"],"pattern":"^(t\\ shirts)$","fields":["category"],"provider":"uniqlo","context":"OUTER_CONTEXT","unless_pattern":""},{"rule_id":"uniqlo.category.shirts","dimension":"garment_type_code","values":["shirt_blouse","polo_shirt"],"pattern":"^(shirts|shirts\\ and\\ polo\\ shirts|shirts\\ and\\ blouses)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.casual_shirts","dimension":"garment_type_code","values":["shirt_blouse"],"pattern":"^(casual\\ shirts|dress\\ shirts)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.polo_shirts","dimension":"garment_type_code","values":["polo_shirt"],"pattern":"^(polo\\ shirts)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.sweaters_and_knitwear","dimension":"garment_type_code","values":["knit_sweater","cardigan","knit_vest"],"pattern":"^(sweaters\\ and\\ knitwear)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.sweatshirts_and_hoodies","dimension":"garment_type_code","values":["sweatshirt","hoodie","zip_hoodie"],"pattern":"^(sweatshirts\\ and\\ hoodies|sweat)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.sweatshirts","dimension":"garment_type_code","values":["sweatshirt"],"pattern":"^(sweatshirts)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.localized_sweatshirt","dimension":"garment_type_code","values":["sweatshirt"],"pattern":"^스웨트셔츠$","fields":["category_locale"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.localized_sweatpants","dimension":"garment_type_code","values":["sweat_jogger_pants"],"pattern":"^(스웨트팬츠|스웨트 팬츠)$","fields":["category_locale"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.jeans","dimension":"garment_type_code","values":["denim_pants"],"pattern":"^(jeans)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.chinos","dimension":"garment_type_code","values":["chino_cotton_pants"],"pattern":"^(chinos)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.jogger_pants","dimension":"garment_type_code","values":["sweat_jogger_pants"],"pattern":"^(jogger\\ pants|sweat\\ pants)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.shorts","dimension":"garment_type_code","values":["shorts","denim_pants","cargo_pants","chino_cotton_pants","sweat_jogger_pants"],"pattern":"^(shorts)$","fields":["category"],"provider":"uniqlo","context":"OUTER_CONTEXT","unless_pattern":""},{"rule_id":"uniqlo.category.leggings_and_tights","dimension":"garment_type_code","values":["leggings"],"pattern":"^(leggings\\ and\\ tights|cropped\\ leggings)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.dresses_and_skirts","dimension":"garment_type_code","values":["dress","skirt"],"pattern":"^(dresses\\ and\\ skirts|dress\\ and\\ skirts)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.skirts","dimension":"garment_type_code","values":["skirt"],"pattern":"^(skirts|flare\\ skirts)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.dresses","dimension":"garment_type_code","values":["dress"],"pattern":"^(dresses)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.boxer_briefs","dimension":"garment_type_code","values":["men_briefs"],"pattern":"^(boxer\\ briefs|boxer)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.trunks","dimension":"garment_type_code","values":["men_trunks"],"pattern":"^(trunks|airism\\ trunks)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.category.hip_hanger","dimension":"garment_type_code","values":["women_panty"],"pattern":"^(hip\\ hanger|just\\ waist)$","fields":["category"],"provider":"uniqlo","context":"INNER_CONTEXT","unless_pattern":""},{"rule_id":"uniqlo.category.loungewear_and_homeware","dimension":"garment_type_code","values":["homewear_top","homewear_bottom"],"pattern":"^(loungewear\\ and\\ homeware|loungewear\\ and\\ pajamas|pajamas)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^(accessories|socks|regular socks|belts|dress belts|umbrella|gloves|scarves and stoles|scarves|bags|shoes|hats)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.node.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"^(short sleeve|half sleeve)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.node.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"^(long sleeve)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.node.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"^(sleeveless)$","fields":["category"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.skirt_tag.mini","dimension":"body_length_code","values":["short_body"],"pattern":"^skirt-length=mini$","fields":["attribute"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.skirt_tag.midi","dimension":"body_length_code","values":["medium_body"],"pattern":"^skirt-length=midi$","fields":["attribute"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.skirt_tag.maxi","dimension":"body_length_code","values":["long_body"],"pattern":"^skirt-length=maxi$","fields":["attribute"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.skirt_tag.long","dimension":"body_length_code","values":["long_body"],"pattern":"^skirt-length=long$","fields":["attribute"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.three_quarter_code","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"^sleeve=3-4$","fields":["attribute"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.full_pant_code","dimension":"lower_length_code","values":["long_length"],"pattern":"^pant-length=full$","fields":["attribute"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.sleeve_label.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"^sleeve=반팔$","fields":["attribute_label"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.sleeve_label.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"^sleeve=긴팔$","fields":["attribute_label"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.sleeve_label.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"^sleeve=슬리브리스$","fields":["attribute_label"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.sleeve_label.three_quarter_sleeve","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"^sleeve=7부$","fields":["attribute_label"],"provider":"uniqlo","context":"ANY","unless_pattern":""},{"rule_id":"uniqlo.inner_panty","dimension":"garment_type_code","values":["women_panty"],"pattern":"(쇼츠|팬티)","fields":["name"],"provider":"uniqlo","context":"INNER_WOMEN","unless_pattern":""},{"rule_id":"musinsa.category.상의","dimension":"garment_type_code","values":["sleeveless_tshirt","tshirt","tank_top","sweatshirt","knit_sweater","shirt_blouse","polo_shirt","hoodie","cardigan","knit_vest","base_layer_top","sports_top","bodysuit_top","zip_hoodie","homewear_top"],"pattern":"^(상의)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.바지","dimension":"garment_type_code","values":["denim_pants","slacks_trousers","chino_cotton_pants","cargo_pants","casual_pants","shorts","sweat_jogger_pants","other_standard_pants","leggings","homewear_bottom"],"pattern":"^(바지|팬츠|하의)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.아우터","dimension":"garment_type_code","values":["jacket","coat","trench_coat","blazer","blouson","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","puffer_vest","outer_vest","mouton","cardigan","zip_hoodie"],"pattern":"^(아우터)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.반소매_티셔츠","dimension":"garment_type_code","values":["tshirt"],"pattern":"^(반소매\\ 티셔츠|긴소매\\ 티셔츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.민소매_티셔츠","dimension":"garment_type_code","values":["tshirt","tank_top","sleeveless_tshirt","bodysuit_top"],"pattern":"^(민소매\\ 티셔츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.셔츠/블라우스","dimension":"garment_type_code","values":["shirt_blouse"],"pattern":"^(셔츠/블라우스|셔츠/블라우스류|셔츠|블라우스)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.피케/카라_티셔츠","dimension":"garment_type_code","values":["polo_shirt"],"pattern":"^(피케/카라\\ 티셔츠|카라\\ 티셔츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.니트/스웨터","dimension":"garment_type_code","values":["knit_sweater","knit_vest"],"pattern":"^(니트/스웨터)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.맨투맨/스웨트셔츠","dimension":"garment_type_code","values":["sweatshirt"],"pattern":"^(맨투맨/스웨트셔츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.맨투맨/스웨트","dimension":"garment_type_code","values":["sweatshirt"],"pattern":"^(맨투맨/스웨트)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.후드_티셔츠","dimension":"garment_type_code","values":["hoodie"],"pattern":"^(후드\\ 티셔츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.후드_집업","dimension":"garment_type_code","values":["zip_hoodie"],"pattern":"^(후드\\ 집업)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.카디건","dimension":"garment_type_code","values":["cardigan"],"pattern":"^(카디건|가디건)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.데님_팬츠","dimension":"garment_type_code","values":["denim_pants"],"pattern":"^(데님\\ 팬츠|청/데님\\ 팬츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.슈트_팬츠/슬랙스","dimension":"garment_type_code","values":["slacks_trousers"],"pattern":"^(슈트\\ 팬츠/슬랙스|슬랙스)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.코튼_팬츠","dimension":"garment_type_code","values":["chino_cotton_pants"],"pattern":"^(코튼\\ 팬츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.트레이닝/조거_팬츠","dimension":"garment_type_code","values":["sweat_jogger_pants"],"pattern":"^(트레이닝/조거\\ 팬츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.트레이닝_팬츠","dimension":"garment_type_code","values":["sweat_jogger_pants"],"pattern":"^(트레이닝\\ 팬츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.숏_팬츠","dimension":"garment_type_code","values":["shorts","denim_pants","cargo_pants","chino_cotton_pants","sweat_jogger_pants"],"pattern":"^(숏\\ 팬츠|쇼트\\ 팬츠)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.스커트","dimension":"garment_type_code","values":["skirt"],"pattern":"^(스커트|미니스커트|미디스커트|롱스커트)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.원피스","dimension":"garment_type_code","values":["dress"],"pattern":"^(원피스|미니원피스|미디원피스|맥시원피스)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.블루종/MA-1","dimension":"garment_type_code","values":["blouson","ma1"],"pattern":"^(블루종/MA\\-1)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.슈트/블레이저_재킷","dimension":"garment_type_code","values":["blazer"],"pattern":"^(슈트/블레이저\\ 재킷)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.나일론/코치_재킷","dimension":"garment_type_code","values":["jacket","windbreaker","anorak"],"pattern":"^(나일론/코치\\ 재킷)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.트러커_재킷","dimension":"garment_type_code","values":["jacket"],"pattern":"^(트러커\\ 재킷|데님/트러커\\ 재킷)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.점퍼/재킷","dimension":"garment_type_code","values":["jacket","coat","trench_coat","blazer","blouson","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","puffer_vest","outer_vest","mouton","zip_hoodie"],"pattern":"^(점퍼/재킷)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.원피스/스커트","dimension":"garment_type_code","values":["dress","skirt"],"pattern":"^(원피스/스커트)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.경량_패딩/패딩_베스트","dimension":"garment_type_code","values":["puffer_jacket","puffer_vest"],"pattern":"^(경량\\ 패딩/패딩\\ 베스트)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.경량_패딩","dimension":"garment_type_code","values":["puffer_jacket"],"pattern":"^(경량\\ 패딩)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.숏패딩/숏헤비_아우터","dimension":"garment_type_code","values":["puffer_jacket"],"pattern":"^(숏패딩/숏헤비\\ 아우터|롱패딩/롱헤비\\ 아우터)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.플리스/뽀글이","dimension":"garment_type_code","values":["fleece_jacket"],"pattern":"^(플리스/뽀글이)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.베스트","dimension":"garment_type_code","values":["outer_vest","knit_vest","puffer_vest"],"pattern":"^(베스트)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.category.코트","dimension":"garment_type_code","values":["coat","trench_coat"],"pattern":"^(코트|겨울\\ 싱글\\ 코트|겨울\\ 기타\\ 코트|환절기\\ 코트|겨울\\ 더블\\ 코트)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.leaf.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"^반소매 티셔츠$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.leaf.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"^긴소매 티셔츠$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.leaf.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"^민소매 티셔츠$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^(신발|스니커즈|구두|가방|모자|스포츠잡화|액세서리|패션소품|주얼리|양말|벨트|뷰티|디지털/테크|생활/취미/예술)$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.TROUSERS","dimension":"garment_type_code","values":["denim_pants","slacks_trousers","chino_cotton_pants","cargo_pants","casual_pants","shorts","sweat_jogger_pants","other_standard_pants","leggings"],"pattern":"^(TROUSERS|PANTS)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.T-SHIRT","dimension":"garment_type_code","values":["tshirt","sleeveless_tshirt","tank_top"],"pattern":"^(T\\-SHIRT)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.SHIRT","dimension":"garment_type_code","values":["shirt_blouse"],"pattern":"^(SHIRT)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.SWEATER","dimension":"garment_type_code","values":["knit_sweater"],"pattern":"^(SWEATER)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.CARDIGAN","dimension":"garment_type_code","values":["cardigan"],"pattern":"^(CARDIGAN)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.SWEATSHIRT","dimension":"garment_type_code","values":["sweatshirt","hoodie","zip_hoodie"],"pattern":"^(SWEATSHIRT)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.SKIRT","dimension":"garment_type_code","values":["skirt"],"pattern":"^(SKIRT)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.DRESS","dimension":"garment_type_code","values":["dress"],"pattern":"^(DRESS)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.BLAZER","dimension":"garment_type_code","values":["blazer"],"pattern":"^(BLAZER)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.WIND-JACKET","dimension":"garment_type_code","values":["jacket","coat","trench_coat","blazer","blouson","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","puffer_vest","outer_vest","mouton","cardigan","zip_hoodie"],"pattern":"^(WIND\\-JACKET|ANORAK)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.BERMUDA","dimension":"garment_type_code","values":["shorts","denim_pants","cargo_pants","chino_cotton_pants","sweat_jogger_pants"],"pattern":"^(BERMUDA|SHORTS)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.WAISTCOAT","dimension":"garment_type_code","values":["outer_vest","knit_vest","puffer_vest"],"pattern":"^(WAISTCOAT)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.KNITTED_WAISTCOAT","dimension":"garment_type_code","values":["knit_vest"],"pattern":"^(KNITTED\\ WAISTCOAT)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.TOPS_AND_OTHERS","dimension":"garment_type_code","values":["sleeveless_tshirt","tshirt","tank_top","sweatshirt","knit_sweater","shirt_blouse","polo_shirt","hoodie","cardigan","knit_vest","base_layer_top","sports_top","bodysuit_top","zip_hoodie","homewear_top","jacket"],"pattern":"^(TOPS\\ AND\\ OTHERS)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.LEGGINGS","dimension":"garment_type_code","values":["leggings"],"pattern":"^(LEGGINGS)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.PANTY/UNDERPANT","dimension":"garment_type_code","values":["men_briefs","men_trunks","women_panty"],"pattern":"^(PANTY/UNDERPANT)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.BRA","dimension":"garment_type_code","values":["women_bra"],"pattern":"^(BRA)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.category.BODYSUIT","dimension":"garment_type_code","values":["bodysuit_top"],"pattern":"^(BODYSUIT)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^(ACCESSORIES|HAND BAG-RUCKSACK|BAG|BAGS|SHOES|PERFUME|COSMETICS|SEAT|TOWEL|AIR FRESHENER|EARRINGS|NECKLACE|BELT|SCARF|HAT|FOOTWEAR|FRAGRANCE)$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.overall_unmapped","dimension":"unsupported_type","values":["jumpsuit"],"pattern":"^OVERALL$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.swim_unmapped","dimension":"unsupported_type","values":["swimwear"],"pattern":"^SWIMSUIT$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.subfamily.denim_pants","dimension":"garment_type_code","values":["denim_pants"],"pattern":"^(B\\.|F\\.) Pants Denim$","fields":["subfamily"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.subfamily.slacks_trousers","dimension":"garment_type_code","values":["slacks_trousers"],"pattern":"^Tailoring Pants$","fields":["subfamily"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.subfamily.knit_vest","dimension":"garment_type_code","values":["knit_vest"],"pattern":"^(KNIT VEST|Knitted Vest)$","fields":["subfamily"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.subfamily.knit_sweater","dimension":"garment_type_code","values":["knit_sweater"],"pattern":"^KNIT SWEATER$","fields":["subfamily"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.subfamily.homewear_top","dimension":"garment_type_code","values":["homewear_top"],"pattern":"^TOP PIJAMA$","fields":["subfamily"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"explicit.knit_vest_sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"(니트[ ]?베스트|knit vest|knitted vest)","fields":["name","subfamily"],"provider":"any","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.skirt_short","dimension":"body_length_code","values":["short_body"],"pattern":"^미니스커트$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.skirt_medium","dimension":"body_length_code","values":["medium_body"],"pattern":"^미디스커트$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.skirt_long","dimension":"body_length_code","values":["long_body"],"pattern":"^롱스커트$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.puffer_short","dimension":"body_length_code","values":["short_body"],"pattern":"^숏패딩/숏헤비 아우터$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"musinsa.puffer_long","dimension":"body_length_code","values":["long_body"],"pattern":"^롱패딩/롱헤비 아우터$","fields":["category"],"provider":"musinsa","context":"ANY","unless_pattern":""},{"rule_id":"explicit.lower_short","dimension":"lower_length_code","values":["short_length"],"pattern":"^(BERMUDA|SHORTS|shorts|숏 팬츠|쇼트 팬츠)$","fields":["category"],"provider":"any","context":"OUTER_CONTEXT","unless_pattern":""},{"rule_id":"zara.localized.가디건.zara.category.CARDIGAN","dimension":"garment_type_code","values":["cardigan"],"pattern":"^가디건$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.니트 베스트.zara.category.KNITTED_WAISTCOAT","dimension":"garment_type_code","values":["knit_vest"],"pattern":"^니트\\ 베스트$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.드레스.zara.category.DRESS","dimension":"garment_type_code","values":["dress"],"pattern":"^드레스$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.레깅스.zara.category.LEGGINGS","dimension":"garment_type_code","values":["leggings"],"pattern":"^레깅스$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.바디.zara.category.BODYSUIT","dimension":"garment_type_code","values":["bodysuit_top"],"pattern":"^바디$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.바지.zara.category.TROUSERS","dimension":"garment_type_code","values":["denim_pants","slacks_trousers","chino_cotton_pants","cargo_pants","casual_pants","shorts","sweat_jogger_pants","other_standard_pants","leggings"],"pattern":"^바지$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.방향제.zara.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^방향제$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.버뮤다반바지.zara.category.BERMUDA","dimension":"garment_type_code","values":["shorts","denim_pants","cargo_pants","chino_cotton_pants","sweat_jogger_pants"],"pattern":"^버뮤다반바지$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.버뮤다반바지.explicit.lower_short","dimension":"lower_length_code","values":["short_length"],"pattern":"^버뮤다반바지$","fields":["category"],"provider":"zara","context":"OUTER_CONTEXT","unless_pattern":""},{"rule_id":"zara.localized.브래지어.zara.category.BRA","dimension":"garment_type_code","values":["women_bra"],"pattern":"^브래지어$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.브레이저.zara.category.BLAZER","dimension":"garment_type_code","values":["blazer"],"pattern":"^브레이저$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.셔츠.zara.category.SHIRT","dimension":"garment_type_code","values":["shirt_blouse"],"pattern":"^셔츠$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.쇼츠.zara.category.BERMUDA","dimension":"garment_type_code","values":["shorts","denim_pants","cargo_pants","chino_cotton_pants","sweat_jogger_pants"],"pattern":"^쇼츠$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.쇼츠.explicit.lower_short","dimension":"lower_length_code","values":["short_length"],"pattern":"^쇼츠$","fields":["category"],"provider":"zara","context":"OUTER_CONTEXT","unless_pattern":""},{"rule_id":"zara.localized.수영복.zara.swim_unmapped","dimension":"unsupported_type","values":["swimwear"],"pattern":"^수영복$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.스웨터.zara.category.SWEATER","dimension":"garment_type_code","values":["knit_sweater"],"pattern":"^스웨터$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.스웨트 셔츠.zara.category.SWEATSHIRT","dimension":"garment_type_code","values":["sweatshirt","hoodie","zip_hoodie"],"pattern":"^스웨트\\ 셔츠$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.스포츠 재킷.zara.category.WIND-JACKET","dimension":"garment_type_code","values":["jacket","coat","trench_coat","blazer","blouson","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","puffer_vest","outer_vest","mouton","cardigan","zip_hoodie"],"pattern":"^스포츠\\ 재킷$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.아노락.zara.category.WIND-JACKET","dimension":"garment_type_code","values":["jacket","coat","trench_coat","blazer","blouson","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","puffer_vest","outer_vest","mouton","cardigan","zip_hoodie"],"pattern":"^아노락$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.악세서리.zara.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^악세서리$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.오버올.zara.overall_unmapped","dimension":"unsupported_type","values":["jumpsuit"],"pattern":"^오버올$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.의자.zara.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^의자$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.조끼.zara.category.WAISTCOAT","dimension":"garment_type_code","values":["outer_vest","knit_vest","puffer_vest"],"pattern":"^조끼$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.치마.zara.category.SKIRT","dimension":"garment_type_code","values":["skirt"],"pattern":"^치마$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.타월.zara.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^타월$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.탑.zara.category.TOPS_AND_OTHERS","dimension":"garment_type_code","values":["sleeveless_tshirt","tshirt","tank_top","sweatshirt","knit_sweater","shirt_blouse","polo_shirt","hoodie","cardigan","knit_vest","base_layer_top","sports_top","bodysuit_top","zip_hoodie","homewear_top","jacket"],"pattern":"^탑$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.티셔츠.zara.category.T-SHIRT","dimension":"garment_type_code","values":["tshirt","sleeveless_tshirt","tank_top"],"pattern":"^티셔츠$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.팬티.zara.category.PANTY/UNDERPANT","dimension":"garment_type_code","values":["men_briefs","men_trunks","women_panty"],"pattern":"^팬티$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.핸드백/베낭.zara.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^핸드백/베낭$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""},{"rule_id":"zara.localized.화장품.zara.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^화장품$","fields":["category"],"provider":"zara","context":"ANY","unless_pattern":""}]}$policy$::jsonb;
 version_value constant text := 'fitmatch-vnext-retailer-api-20260909-r1';
 status_value text; reason_value text; candidate_values jsonb := '[]'::jsonb;
 tuple_value jsonb; fixed_value jsonb; unknown_value jsonb;
 conflict boolean := false; product_specific boolean := false; invalid_evidence boolean := false;
BEGIN
 -- The deployed verified-mapping algorithm is retained verbatim as the first authority.
 SELECT old_decision.value INTO base FROM (with recursive product_row as (
    select p.*
    from fitmatch_vnext.products p
    where p.source_code = p_source_code
      and p.source_product_key = p_source_product_key
),

comparison_unit as (
    select
        p.id,
        fitmatch_vnext.product_comparison_unit_decision(p.id) unit
    from product_row p
),

evidence as (
    select
        p.id product_id,
        pcs.source_signal_id,
        pcs.evidence_order,
        ss.signal_kind,
        ss.external_key,

        case ss.signal_kind
            when 'PRODUCT_EXACT' then 600
            when 'PRODUCT_STRUCTURE' then 500
            when 'PRODUCT_TYPE' then 400
            when 'SUBFAMILY' then 300
            when 'FAMILY' then 250
            when 'CATEGORY' then 200
            when 'SECTION' then 150
            else 100
        end evidence_rank

    from product_row p

    join fitmatch_vnext.product_classification_signals pcs
      on pcs.product_id = p.id

    join fitmatch_vnext.source_classification_signals ss
      on ss.id = pcs.source_signal_id
     and ss.source_code = p.source_code
     and ss.is_active
),

raw_candidates as (
    select
        e.*,
        m.id mapping_id,
        m.resolution_mode,
        m.garment_type_code,
        m.sleeve_length_code,
        m.lower_length_code,
        m.body_length_code,
        m.priority,
        m.mapping_version,
        m.mapping_checksum

    from evidence e

    join product_row p
      on p.id = e.product_id

    join fitmatch_vnext.classification_signal_mappings m
      on m.source_signal_id = e.source_signal_id
     and m.is_active
     and m.is_verified
     and (
         m.audience_code = 'ANY'
         or m.audience_code = p.audience_code
     )
     and (
         coalesce(m.mapping_version, '')
            <> 'vnext-uniqlo-complete-path-20260902-v3'
         or fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current(m.id)
     )
),

signal_ancestry(
    descendant_id,
    ancestor_id,
    depth
) as (
    select
        s.id,
        s.parent_signal_id,
        1
    from fitmatch_vnext.source_classification_signals s
    where s.parent_signal_id is not null

    union all

    select
        a.descendant_id,
        s.parent_signal_id,
        a.depth + 1

    from signal_ancestry a

    join fitmatch_vnext.source_classification_signals s
      on s.id = a.ancestor_id

    where s.parent_signal_id is not null
      and a.depth < 16
),

candidates as (
    select
        c.*,
        max(c.evidence_rank) over () max_evidence_rank

    from raw_candidates c

    where not exists (
        select 1
        from raw_candidates d

        join signal_ancestry a
          on a.descendant_id = d.source_signal_id
         and a.ancestor_id = c.source_signal_id

        where d.product_id = c.product_id
          and c.resolution_mode = 'PRODUCT_REQUIRED'
          and d.resolution_mode = 'DIRECT'
          and d.evidence_rank = c.evidence_rank
          and d.priority = c.priority
    )
),

ranked as (
    select
        c.*,
        max(priority) over () max_priority

    from candidates c

    where evidence_rank = max_evidence_rank
),

top_candidates as (
    select *
    from ranked
    where priority = max_priority
),

summary as (
    select
        count(*) candidate_count,

        count(
            distinct concat_ws(
                '|',
                resolution_mode,
                coalesce(garment_type_code, '∅'),
                coalesce(sleeve_length_code, '∅'),
                coalesce(lower_length_code, '∅'),
                coalesce(body_length_code, '∅')
            )
        ) outcome_count

    from top_candidates
),

chosen as (
    select *
    from top_candidates

    order by
        case
            when lower(p_source_code) = 'uniqlo'
             and signal_kind = 'CATEGORY'
            then evidence_order
        end desc nulls last,

        evidence_order,
        source_signal_id,
        mapping_id

    limit 1
),

resolved as (
    select
        p.*,
        unit.unit comparison_unit,

        c.source_signal_id,
        c.mapping_id,
        c.resolution_mode mapping_resolution_mode,

        c.garment_type_code mapped_garment_type_code,
        c.sleeve_length_code mapped_sleeve_length_code,
        c.lower_length_code mapped_lower_length_code,
        c.body_length_code mapped_body_length_code,

        c.mapping_version,
        c.mapping_checksum,

        coalesce(s.candidate_count, 0) candidate_count,
        coalesce(s.outcome_count, 0) outcome_count

    from product_row p

    left join comparison_unit unit
      on unit.id = p.id

    left join summary s
      on true

    left join chosen c
      on true
),

decision as (
    select
        r.*,

        case
            when upper(coalesce(r.product_structure_code, 'UNKNOWN')) = 'SET'
                then 'NOT_APPLICABLE'

            when r.candidate_count = 0
                then 'REVIEW_REQUIRED'

            when r.outcome_count > 1
                then 'REVIEW_REQUIRED'

            when r.mapping_resolution_mode = 'NOT_APPLICABLE'
                then 'NOT_APPLICABLE'

            when r.mapping_resolution_mode = 'DIRECT'
             and coalesce(
                (
                    fitmatch_vnext.classification_tuple_validation(
                        r.mapped_garment_type_code,
                        r.product_structure_code,
                        r.audience_code,
                        r.mapped_sleeve_length_code,
                        r.mapped_lower_length_code,
                        r.mapped_body_length_code
                    ) ->> 'valid'
                )::boolean,
                false
             )
                then 'CONFIRMED'

            else 'REVIEW_REQUIRED'
        end decision_status,

        case
            when upper(coalesce(r.product_structure_code, 'UNKNOWN')) = 'SET'
                then 'Product structure is SET'

            when r.candidate_count = 0
                then 'No active verified mapping candidate'

            when r.outcome_count > 1
                then 'Equal-top candidates have different outcomes'

            when r.mapping_resolution_mode = 'NOT_APPLICABLE'
                then 'Mapping is NOT_APPLICABLE'

            when r.mapping_resolution_mode = 'DIRECT'
             and coalesce(
                (
                    fitmatch_vnext.classification_tuple_validation(
                        r.mapped_garment_type_code,
                        r.product_structure_code,
                        r.audience_code,
                        r.mapped_sleeve_length_code,
                        r.mapped_lower_length_code,
                        r.mapped_body_length_code
                    ) ->> 'valid'
                )::boolean,
                false
             )
                then 'Complete verified DIRECT classification mapping'

            when r.mapping_resolution_mode = 'DIRECT'
                then 'DIRECT classification tuple is invalid'

            when r.mapping_resolution_mode = 'PRODUCT_REQUIRED'
                then 'Product-exact verified evidence is required'

            else 'Mapping requires review'
        end decision_reason

    from resolved r
)

select case

    when not exists (
        select 1 from product_row
    )
    then jsonb_build_object(
        'found', false,
        'classification_status', 'REVIEW_REQUIRED',
        'resolution_mode', 'REVIEW_REQUIRED',
        'reason', 'Unknown source product identity',
        'resolver_version',
            'fitmatch-vnext-resolver-v4-classification-only-uniqlo-deepest-category'
    )

    else (
        select jsonb_strip_nulls(
            jsonb_build_object(
                'found', true,
                'product_id', d.id,
                'source_code', d.source_code,
                'source_product_key', d.source_product_key,

                'classification_status', d.decision_status,

                'resolution_mode',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then 'DIRECT'
                        when d.decision_status = 'NOT_APPLICABLE'
                            then 'NOT_APPLICABLE'
                        else coalesce(
                            d.mapping_resolution_mode,
                            'REVIEW_REQUIRED'
                        )
                    end,

                'garment_type_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_garment_type_code
                    end,

                'product_structure_code',
                    d.product_structure_code,

                'comparison_measurement_contract',
                    d.comparison_unit ->> 'measurement_contract',

                'comparison_unit_eligible',
                    d.comparison_unit -> 'eligible',

                'audience_code',
                    d.audience_code,

                'sleeve_length_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_sleeve_length_code
                    end,

                'lower_length_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_lower_length_code
                    end,

                'body_length_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_body_length_code
                    end,

                'primary_source_signal_id',
                    d.source_signal_id,

                'mapping_id',
                    d.mapping_id,

                'mapping_version',
                    d.mapping_version,

                'mapping_checksum',
                    d.mapping_checksum,

                'reason',
                    d.decision_reason,

                'resolver_version',
                    'fitmatch-vnext-resolver-v4-classification-only-uniqlo-deepest-category',

                'input_fingerprint',
                    encode(
                        extensions.digest(
                            concat_ws(
                                '|',
                                d.source_code,
                                d.source_product_key,
                                d.audience_code,
                                d.product_structure_code,
                                coalesce(
                                    d.source_signal_id::text,
                                    '∅'
                                ),
                                coalesce(
                                    d.mapping_checksum,
                                    '∅'
                                ),
                                'fitmatch-vnext-resolver-v4-classification-only-uniqlo-deepest-category'
                            ),
                            'sha256'
                        ),
                        'hex'
                    )
            )
        )

        from decision d
    )

end) old_decision(value);
 IF NOT coalesce((base->>'found')::boolean,false) THEN RETURN base; END IF;
 SELECT * INTO product_row FROM fitmatch_vnext.products WHERE id=(base->>'product_id')::uuid;

 -- Installing this function cannot invalidate existing personal choices or reclassify
 -- stored rows. Existing ingress clears resolver_version only for a NEW observation.
 IF product_row.resolver_version IS NOT NULL AND product_row.resolver_version<>version_value
 THEN RETURN base; END IF;
 IF product_row.source_code NOT IN ('uniqlo','musinsa','zara') THEN RETURN base; END IF;

 -- Existing service-only ingress atomically writes these CURRENT projection fields
 -- and the immutable receipt. Read the public product projection, not the private
 -- receipt table: this existing SECURITY INVOKER reader retains its original grants.
 -- Never use _legacy_source_category_path or carried-forward migration metadata.
 IF coalesce(product_row.source_extra->>'latest_ingestion_fingerprint','') !~ '^[0-9a-f]{64}$'
    OR (product_row.source_extra->>'latest_ingestion_observed_at')::timestamptz
         IS DISTINCT FROM product_row.last_fetched_at
    OR product_row.last_fetched_at IS NULL
 THEN RETURN base; END IF;

 -- Read full retailer API JSON; no Swift/local classification is accepted here.
 envelope:=product_row.source_extra#>'{structured_facts,retailer_api}';
 IF jsonb_typeof(envelope) IS DISTINCT FROM 'object'
    OR envelope->>'contract_version' IS DISTINCT FROM 'fitmatch-retailer-api-v1'
    OR envelope->>'source_code' IS DISTINCT FROM product_row.source_code
    OR envelope->>'source_product_key' IS DISTINCT FROM product_row.source_product_key
    OR envelope#>>'{requests,details,http_status}' IS DISTINCT FROM '200'
    OR jsonb_typeof(envelope->'details') IS DISTINCT FROM 'object'
 THEN invalid_evidence:=true;
 ELSE
  DECLARE
   api_product jsonb; api_selected jsonb; api_facts jsonb := '[]'::jsonb;
   api_audience text; api_components jsonb := '[]'::jsonb; api_measure_codes jsonb;
  BEGIN
   IF product_row.source_code='uniqlo' THEN
    api_product:=envelope#>'{details,result}';
    IF api_product->>'productId' IS DISTINCT FROM product_row.source_product_key||'-000'
       OR jsonb_typeof(api_product->'breadcrumbs') IS DISTINCT FROM 'object'
       OR jsonb_typeof(coalesce(api_product->'tags','[]'::jsonb))<>'array'
    THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='UNIQLO_API_IDENTITY_OR_SHAPE'; END IF;
    api_audience:=api_product->>'genderCategory';
    -- Product audience, sizing gender and navigation membership are separate.
    SELECT coalesce(jsonb_agg(f),'[]'::jsonb) INTO api_facts FROM (
     SELECT jsonb_build_object('field','category','value',node->>'name',
        'source_path','$.result.breadcrumbs.'||level_name||'.name') f
     FROM (VALUES ('class'),('category'),('subcategory')) levels(level_name)
     CROSS JOIN LATERAL (SELECT api_product->'breadcrumbs'->level_name node) n
     WHERE nullif(node->>'name','') IS NOT NULL
     UNION ALL
     SELECT jsonb_build_object('field','category_locale','value',node->>'locale',
        'source_path','$.result.breadcrumbs.'||level_name||'.locale')
     FROM (VALUES ('class'),('category'),('subcategory')) levels(level_name)
     CROSS JOIN LATERAL (SELECT api_product->'breadcrumbs'->level_name node) n
     WHERE nullif(node->>'locale','') IS NOT NULL
     UNION ALL
     SELECT jsonb_build_object('field','attribute','value',(tag->>'group')||'='||(tag->>'tag'),
        'source_path','$.result.tags['||(ordinality-1)||']')
     FROM jsonb_array_elements(coalesce(api_product->'tags','[]'::jsonb)) WITH ORDINALITY t(tag,ordinality)
     WHERE nullif(tag->>'group','') IS NOT NULL AND nullif(tag->>'tag','') IS NOT NULL
     UNION ALL
     SELECT jsonb_build_object('field','attribute_label','value',(tag->>'group')||'='||(tag->>'tagName'),
        'source_path','$.result.tags['||(ordinality-1)||'].tagName')
     FROM jsonb_array_elements(coalesce(api_product->'tags','[]'::jsonb)) WITH ORDINALITY t(tag,ordinality)
     WHERE nullif(tag->>'group','') IS NOT NULL AND nullif(tag->>'tagName','') IS NOT NULL
     UNION ALL
     SELECT jsonb_build_object('field','name','value',api_product->>'name','source_path','$.result.name')
     UNION ALL
     SELECT jsonb_build_object('field','description','value',api_product->>k,'source_path','$.result.'||k)
     FROM (VALUES ('longDescription'),('designDetail')) descriptions(k)
     WHERE nullif(api_product->>k,'') IS NOT NULL
    ) facts;
    -- A pajama product reporting BOTH upper and explicitly [bottoms] garment
    -- measurements is a composite. BODY measurements never participate.
    SELECT coalesce(jsonb_agg(DISTINCT part->>'code'),'[]'::jsonb) INTO api_measure_codes
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(envelope#>'{measurements,result}')='array'
         THEN envelope#>'{measurements,result}' ELSE '[]'::jsonb END) chart
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(chart->'sizeChart','[]'::jsonb)) sz
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(sz->'sizeParts','[]'::jsonb)) part
    WHERE chart->>'productId'=product_row.source_product_key||'-000';
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(api_facts) f WHERE f->>'field'='category'
        AND f->>'value' IN ('loungewear and homeware','loungewear and pajamas','pajamas'))
       AND api_measure_codes ? 'waist-product-size-bottoms'
       AND api_measure_codes ? 'body-width'
       AND api_measure_codes ?| ARRAY['sleeve-length-cb','shoulder-width']
    THEN api_components:=jsonb_build_array(
       jsonb_build_object('component_id','upper','measurement_contract_id','garment-upper'),
       jsonb_build_object('component_id','lower','measurement_contract_id','garment-lower'));
    END IF;
   ELSIF product_row.source_code='musinsa' THEN
    api_product:=envelope#>'{details,data}';
    IF api_product->>'goodsNo' IS DISTINCT FROM product_row.source_product_key
       OR jsonb_typeof(api_product->'sex') IS DISTINCT FROM 'array'
    THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MUSINSA_API_IDENTITY_OR_SHAPE'; END IF;
    SELECT CASE WHEN count(*) FILTER(WHERE sex NOT IN ('남성','여성'))=0
       AND bool_or(sex='남성') AND bool_or(sex='여성') THEN 'UNISEX'
      WHEN count(*) FILTER(WHERE sex<>'남성')=0 AND count(*)>0 THEN 'MEN'
      WHEN count(*) FILTER(WHERE sex<>'여성')=0 AND count(*)>0 THEN 'WOMEN'
      ELSE 'UNKNOWN' END INTO api_audience
    FROM jsonb_array_elements_text(api_product->'sex') sex;
    SELECT coalesce(jsonb_agg(f),'[]'::jsonb) INTO api_facts FROM (
     SELECT jsonb_build_object('field','category','value',api_product->'category'->>k,
        'source_path','$.data.category.'||k) f
     FROM (VALUES ('categoryDepth1Name'),('categoryDepth2Name'),('categoryDepth3Name'),('categoryDepth4Name')) levels(k)
     WHERE nullif(api_product->'category'->>k,'') IS NOT NULL
     UNION ALL
     SELECT jsonb_build_object('field','category','value',btrim(v),'source_path','$.data.baseCategoryFullPath['||(ordinality-1)||']')
     FROM regexp_split_to_table(coalesce(api_product->>'baseCategoryFullPath',''),'\s*>\s*') WITH ORDINALITY p(v,ordinality)
     WHERE btrim(v)<>''
     UNION ALL
     SELECT jsonb_build_object('field','name','value',api_product->>k,'source_path','$.data.'||k)
     FROM (VALUES ('goodsNm'),('goodsNmEng')) titles(k) WHERE nullif(api_product->>k,'') IS NOT NULL
     UNION ALL
     SELECT jsonb_build_object('field','attribute','value',(g->>'name')||'='||(item->>'name'),
       'source_path','$.data.goodsMaterial.materials['||(gi-1)||'].items['||(ii-1)||']')
     FROM jsonb_array_elements(coalesce(api_product#>'{goodsMaterial,materials}','[]'::jsonb)) WITH ORDINALITY gs(g,gi)
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(g->'items','[]'::jsonb)) WITH ORDINALITY its(item,ii)
     WHERE item->'isSelected'='true'::jsonb
     UNION ALL
     SELECT jsonb_build_object('field','description','value',api_product->>'specDesc','source_path','$.data.specDesc')
     WHERE nullif(api_product->>'specDesc','') IS NOT NULL
    ) facts;
    -- Image markup, merchant promotions and size-template titles are retained
    -- in raw JSON, but are not reliable product classification authority.
   ELSIF product_row.source_code='zara' THEN
    api_product:=envelope#>'{details,product}';
    IF api_product->>'type' IS DISTINCT FROM 'Product'
       OR jsonb_typeof(api_product#>'{detail,colors}') IS DISTINCT FROM 'array'
       OR (SELECT count(*) FROM jsonb_array_elements(api_product#>'{detail,colors}') c
           WHERE c->>'productId'=product_row.source_product_key)<>1
    THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ZARA_API_IDENTITY_OR_SHAPE'; END IF;
    SELECT c INTO api_selected FROM jsonb_array_elements(api_product#>'{detail,colors}') c
      WHERE c->>'productId'=product_row.source_product_key;
    api_audience:=CASE api_product->>'sectionName' WHEN 'MAN' THEN 'MEN' WHEN 'WOMAN' THEN 'WOMEN'
      WHEN 'KID' THEN 'KIDS' WHEN 'KIDS' THEN 'KIDS' WHEN 'BABY' THEN 'BABY' ELSE 'UNKNOWN' END;
    api_facts:=jsonb_build_array(
      jsonb_build_object('field','name','value',api_product->>'name','source_path','$.product.name'),
      jsonb_build_object('field','category','value',api_product->>'familyName','source_path','$.product.familyName'));
    IF nullif(api_product->>'subfamilyName','') IS NOT NULL THEN
      api_facts:=api_facts||jsonb_build_array(jsonb_build_object('field','subfamily','value',api_product->>'subfamilyName','source_path','$.product.subfamilyName'));
    END IF;
    SELECT api_facts||coalesce(jsonb_agg(f),'[]'::jsonb) INTO api_facts FROM (
     SELECT jsonb_build_object('field','description','value',v,'source_path',p) f
     FROM (VALUES (api_product->>'description','$.product.description'),
       (api_product#>>'{detail,description}','$.product.detail.description'),
       (api_product#>>'{detail,longDescription}','$.product.detail.longDescription'),
       (coalesce(api_selected->>'rawDescription',api_selected->>'description'),
          '$.product.detail.colors[productId='||product_row.source_product_key||'].description')) d(v,p)
     WHERE nullif(v,'') IS NOT NULL
    ) facts;
   END IF;
   api_facts:=api_facts||jsonb_build_array(jsonb_build_object('field','audience','value',coalesce(api_audience,'UNKNOWN'),
      'source_path',CASE product_row.source_code WHEN 'uniqlo' THEN '$.result.genderCategory'
        WHEN 'musinsa' THEN '$.data.sex' ELSE '$.product.sectionName' END));
   p_observation:=jsonb_build_object('contract_version','retailer-facts-2026-v1','source_code',product_row.source_code,
      'source_product_key',product_row.source_product_key,'identity_verified',true,'fetch_state','FETCHED',
      'facts',api_facts,'components',api_components);
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '22004' THEN invalid_evidence:=true;
  END;
 END IF;

 -- The normalized audience must agree with the persisted ingress audience. UNKNOWN
 -- is kept unknown. No provider code U or navigation label becomes a new audience.
 IF NOT invalid_evidence AND jsonb_typeof(p_observation->'facts')='array' THEN
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_observation->'facts') f
       WHERE f->>'field'='audience' AND f->>'value' IS DISTINCT FROM product_row.audience_code)
   THEN invalid_evidence:=true;
   ELSE
     p_observation:=jsonb_set(p_observation,'{facts}',p_observation->'facts'||jsonb_build_array(
         jsonb_build_object('field','name','value',product_row.product_name,'source_path','$.product_name'),
         jsonb_build_object('field','audience','value',product_row.audience_code,'source_path','$.audience')));
   END IF;
 END IF;

 IF NOT invalid_evidence THEN
   BEGIN
     
DECLARE result jsonb;
BEGIN
 IF p_observation IS NULL OR jsonb_typeof(p_observation) IS DISTINCT FROM 'object'
    OR p_observation->>'contract_version' IS DISTINCT FROM 'retailer-facts-2026-v1'
    OR coalesce(p_observation->>'source_code','') NOT IN ('uniqlo','musinsa','zara')
    OR length(coalesce(p_observation->>'source_product_key',''))=0
    OR jsonb_typeof(p_observation->'facts') IS DISTINCT FROM 'array'
    OR jsonb_typeof(coalesce(p_observation->'components','[]'::jsonb)) IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INVALID_INPUT'; END IF;
 IF jsonb_array_length(p_observation->'facts')>256
    OR jsonb_array_length(coalesce(p_observation->'components','[]'::jsonb))>32
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INPUT_TOO_LARGE'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_observation->'facts') f
    WHERE jsonb_typeof(f) IS DISTINCT FROM 'object'
       OR jsonb_typeof(f->'field') IS DISTINCT FROM 'string'
       OR jsonb_typeof(f->'value') IS DISTINCT FROM 'string'
       OR jsonb_typeof(f->'source_path') IS DISTINCT FROM 'string'
       OR length(f->>'value')>16000 OR length(f->>'source_path')=0)
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INVALID_FACT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c
    WHERE jsonb_typeof(c) IS DISTINCT FROM 'object'
       OR jsonb_typeof(c->'component_id') IS DISTINCT FROM 'string'
       OR length(coalesce(c->>'component_id',''))=0
       OR jsonb_typeof(c->'measurement_contract_id') IS DISTINCT FROM 'string'
       OR length(coalesce(c->>'measurement_contract_id',''))=0)
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c
        GROUP BY c->>'component_id' HAVING count(*)>1)
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INVALID_COMPONENTS'; END IF;
 IF p_observation->>'fetch_state' IS DISTINCT FROM 'FETCHED'
    OR p_observation->'identity_verified' IS DISTINCT FROM 'true'::jsonb
 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='FM_CLASSIFIER_UNVERIFIED_INPUT'; END IF;

 -- Numeric measurements are retained as API evidence. No validated five-way
 -- garment-length calibration exists: they cannot fabricate a length axis.
 IF p_observation ? 'measurement_evidence' THEN
   IF jsonb_typeof(p_observation->'measurement_evidence') IS DISTINCT FROM 'object'
      OR p_observation#>>'{measurement_evidence,source_code}' IS DISTINCT FROM p_observation->>'source_code'
      OR p_observation#>>'{measurement_evidence,source_product_key}' IS DISTINCT FROM p_observation->>'source_product_key'
      OR jsonb_typeof(p_observation#>'{measurement_evidence,records}') IS DISTINCT FROM 'array'
   THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='FM_CLASSIFIER_INVALID_MEASUREMENT_EVIDENCE'; END IF;
   IF jsonb_array_length(p_observation#>'{measurement_evidence,records}')>8192
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_observation#>'{measurement_evidence,records}') m
        WHERE jsonb_typeof(m) IS DISTINCT FROM 'object'
          OR coalesce(m->>'scope','') NOT IN ('GARMENT','BODY','UNKNOWN')
          OR jsonb_typeof(m->'source_path') IS DISTINCT FROM 'string'
          OR coalesce(m->>'source_path','')='')
   THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='FM_CLASSIFIER_INVALID_MEASUREMENT_EVIDENCE'; END IF;
 END IF;

 WITH rules AS (
   SELECT * FROM jsonb_to_recordset(policy_value->'rules')
    AS r(rule_id text, dimension text, "values" jsonb, pattern text,
         fields jsonb, unless_pattern text, context text, provider text)
 ), facts AS (
   SELECT DISTINCT f->>'field' field,f->>'value' value,f->>'source_path' source_path
   FROM jsonb_array_elements(p_observation->'facts') f
 ), context AS (
   SELECT coalesce(bool_or(field='category' AND value ~* '^(이너웨어|언더웨어|이너웨어 상의|INNER TOPS|INNERWEAR|UNDERWEAR)$'),false) inner_context
   FROM facts
 ), raw_hits AS (
   SELECT r.rule_id,r.dimension,r."values",f.field,f.value,f.source_path
   FROM facts f CROSS JOIN rules r CROSS JOIN context c
   WHERE r.fields ? f.field AND f.value ~* r.pattern
     AND r.provider IN ('any',p_observation->>'source_code')
     AND (r.unless_pattern='' OR NOT f.value ~* r.unless_pattern)
     AND (r.context='ANY' OR (r.context='INNER_CONTEXT' AND c.inner_context)
          OR (r.context='OUTER_CONTEXT' AND NOT c.inner_context)
          OR (r.context='INNER_WOMEN' AND c.inner_context AND product_row.audience_code='WOMEN'))
 ), ranked_hits AS (
   SELECT h.*,CASE WHEN source_path LIKE '%.subcategory.%' THEN 4
      WHEN source_path LIKE '%.category.%' THEN 3 WHEN source_path LIKE '%.class.%' THEN 2 ELSE 0 END category_depth
   FROM raw_hits h
 ), hits AS (
   SELECT rule_id,dimension,"values",field,value,source_path FROM ranked_hits h
   WHERE p_observation->>'source_code'<>'uniqlo' OR dimension<>'garment_type_code'
      OR field NOT IN ('category','category_locale') OR (
       category_depth=(SELECT max(category_depth) FROM ranked_hits x WHERE x.dimension='garment_type_code' AND x.field IN ('category','category_locale'))
       AND NOT (category_depth=2 AND EXISTS(SELECT 1 FROM ranked_hits x WHERE x.dimension='garment_type_code' AND x.field='name'))
       AND (field='category_locale' OR NOT EXISTS(SELECT 1 FROM ranked_hits x WHERE x.dimension='garment_type_code' AND x.field='category_locale' AND x.category_depth=h.category_depth))
      )
 ), dimensions AS (
   SELECT dimension, jsonb_agg(DISTINCT v ORDER BY v) possible_values
   FROM hits h CROSS JOIN LATERAL jsonb_array_elements(h."values") v
   WHERE NOT EXISTS(SELECT 1 FROM hits h2 WHERE h2.dimension=h.dimension AND NOT h2."values" @> jsonb_build_array(v))
   GROUP BY dimension
 ), garments AS (
   SELECT gt.* FROM fitmatch_vnext.garment_types gt
   JOIN dimensions d ON d.dimension='garment_type_code' AND d.possible_values ? gt.garment_type_code
   WHERE gt.is_active
 ), axes AS (
   SELECT axis_code,value_code FROM fitmatch_vnext.classification_axis_value_authority
   WHERE is_active AND is_verified
 ), audiences AS (
   SELECT DISTINCT value FROM facts WHERE field='audience'
     AND value IN ('MEN','WOMEN','UNISEX','KIDS','BABY')
 ), component_summary AS (
   SELECT count(DISTINCT c->>'component_id') FILTER(WHERE nullif(c->>'component_id','') IS NOT NULL) component_count,
     count(DISTINCT c->>'measurement_contract_id') FILTER(WHERE nullif(c->>'component_id','') IS NOT NULL AND nullif(c->>'measurement_contract_id','') IS NOT NULL) contract_count
   FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c
 ), checks AS (
   SELECT
     EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion') OR
       (SELECT component_count>1 AND contract_count>1 FROM component_summary) excluded,
     EXISTS(SELECT 1 FROM hits WHERE dimension='unsupported_type') unsupported,
     EXISTS(SELECT 1 FROM facts f WHERE field='attribute' AND (value LIKE 'sleeve=%' OR value LIKE 'pant-length=%')
       AND NOT EXISTS(SELECT 1 FROM hits h WHERE h.source_path=f.source_path AND h.value=f.value
         AND h.dimension=CASE WHEN f.value LIKE 'sleeve=%' THEN 'sleeve_length_code' ELSE 'lower_length_code' END)) unknown_sleeve_attribute,
     EXISTS(SELECT 1 FROM hits WHERE dimension='structure' AND "values" ? 'AMBIGUOUS_BUNDLE') ambiguous_bundle,
     EXISTS(SELECT 1 FROM raw_hits WHERE dimension='garment_type_code' AND field IN ('category','category_locale')) category_corroborated,
     (SELECT count(*)=1 FROM audiences) audience_valid,
     (SELECT count(*) FROM garments) garment_count,
     EXISTS(SELECT 1 FROM hits WHERE dimension='garment_type_code') AND NOT EXISTS(SELECT 1 FROM garments) type_conflict
 ), complete_candidates AS (
   SELECT jsonb_build_object('audience_code',a.value,'category_code',g.category_code,
      'garment_type_code',g.garment_type_code,'comparison_policy_code',g.comparison_policy_code,
      'sleeve_length_code',s.value_code,'lower_length_code',l.value_code,'body_length_code',b.value_code) tuple
   FROM garments g CROSS JOIN audiences a CROSS JOIN checks ch
   CROSS JOIN LATERAL (SELECT value_code FROM axes WHERE axis_code='sleeve_length' AND g.uses_sleeve_length
       UNION ALL SELECT NULL WHERE NOT g.uses_sleeve_length) s
   CROSS JOIN LATERAL (SELECT value_code FROM axes WHERE axis_code='lower_length' AND g.uses_lower_length
       UNION ALL SELECT NULL WHERE NOT g.uses_lower_length) l
   CROSS JOIN LATERAL (SELECT value_code FROM axes WHERE axis_code='body_length' AND g.uses_body_length
       UNION ALL SELECT NULL WHERE NOT g.uses_body_length) b
   WHERE ch.audience_valid AND ch.category_corroborated AND NOT ch.excluded
     AND (g.garment_type_code NOT IN ('sleeveless_tshirt','tank_top','knit_vest','women_camisole') OR s.value_code='sleeveless')
     AND NOT ch.unsupported AND NOT ch.ambiguous_bundle AND NOT ch.unknown_sleeve_attribute
     AND (g.garment_type_code NOT LIKE 'men\_%' ESCAPE '\' OR a.value='MEN')
     AND (g.garment_type_code NOT LIKE 'women\_%' ESCAPE '\' OR a.value='WOMEN')
     AND (NOT g.uses_sleeve_length OR NOT EXISTS(SELECT 1 FROM hits WHERE dimension='sleeve_length_code')
          OR EXISTS(SELECT 1 FROM dimensions d WHERE d.dimension='sleeve_length_code' AND d.possible_values ? s.value_code))
     AND (NOT g.uses_lower_length OR NOT EXISTS(SELECT 1 FROM hits WHERE dimension='lower_length_code')
          OR EXISTS(SELECT 1 FROM dimensions d WHERE d.dimension='lower_length_code' AND d.possible_values ? l.value_code))
     AND (NOT g.uses_body_length OR NOT EXISTS(SELECT 1 FROM hits WHERE dimension='body_length_code')
          OR EXISTS(SELECT 1 FROM dimensions d WHERE d.dimension='body_length_code' AND d.possible_values ? b.value_code))
 ), candidate_summary AS (
   SELECT coalesce(jsonb_agg(tuple ORDER BY tuple::text),'[]'::jsonb) candidates,count(*) count FROM complete_candidates
 ), fingerprints AS (
   SELECT encode(sha256(convert_to(jsonb_build_object(
     'source_code',p_observation->>'source_code','source_product_key',p_observation->>'source_product_key',
     'contract_version',p_observation->>'contract_version',
     'facts',(SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY field,source_path,value),'[]'::jsonb) FROM facts f),
     'components',(SELECT coalesce(jsonb_agg(c ORDER BY c::text),'[]'::jsonb) FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c),
     'measurements',(SELECT coalesce(jsonb_agg(m ORDER BY m::text),'[]'::jsonb) FROM jsonb_array_elements(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)) m)
     )::text,'UTF8')),'hex') input_fingerprint,
     encode(sha256(convert_to(jsonb_build_object('rules',policy_value,
       'garments',(SELECT jsonb_agg(to_jsonb(g) - 'created_at' - 'updated_at' ORDER BY garment_type_code) FROM fitmatch_vnext.garment_types g WHERE is_active),
       'axes',(SELECT jsonb_agg(to_jsonb(a) ORDER BY axis_code,value_code) FROM axes a))::text,'UTF8')),'hex') policy_fingerprint
 ), known AS (
   SELECT dimension,jsonb_agg(v ORDER BY v)->0 value FROM dimensions CROSS JOIN LATERAL jsonb_array_elements(possible_values) v
   WHERE dimension IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
   GROUP BY dimension HAVING count(*)=1
   UNION ALL SELECT 'audience_code',to_jsonb(min(value)) FROM audiences HAVING count(*)=1
 ), common_candidate_fields AS (
   SELECT k,jsonb_agg(DISTINCT v)->0 v FROM complete_candidates c CROSS JOIN LATERAL jsonb_each(c.tuple) e(k,v)
   GROUP BY k HAVING count(DISTINCT v)=1 AND jsonb_agg(DISTINCT v)->0 <> 'null'::jsonb
 ), missing AS (
   SELECT k FROM complete_candidates c CROSS JOIN LATERAL jsonb_each(c.tuple) e(k,v)
   WHERE k IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
   GROUP BY k HAVING count(DISTINCT v)>1
 ), reasons AS (
   SELECT 'NON_APPAREL' code WHERE EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion' AND "values" ? 'NON_APPAREL')
   UNION SELECT 'UPPER_LOWER_SET' WHERE EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion' AND "values" ? 'UPPER_LOWER_SET')
   UNION SELECT 'MULTIPLE_COMPONENT_MEASUREMENT_CONTRACTS' WHERE (SELECT component_count>1 AND contract_count>1 FROM component_summary)
   UNION SELECT 'UNSUPPORTED_GARMENT_TYPE' WHERE (SELECT unsupported FROM checks)
   UNION SELECT 'UNSUPPORTED_RETAILER_AXIS' WHERE (SELECT unknown_sleeve_attribute FROM checks)
   UNION SELECT 'BUNDLE_CONTENTS_UNPROVEN' WHERE (SELECT ambiguous_bundle AND NOT excluded FROM checks)
   UNION SELECT 'TYPE_EVIDENCE_CONFLICT' WHERE (SELECT type_conflict FROM checks)
   UNION SELECT 'MISSING_OR_CONFLICTING_AUDIENCE' WHERE NOT (SELECT audience_valid FROM checks)
   UNION SELECT 'NO_CORROBORATED_TYPE_EVIDENCE' WHERE NOT (SELECT category_corroborated FROM checks)
   UNION SELECT 'TUPLE_OR_AXIS_UNRESOLVED' WHERE (SELECT count=0 FROM candidate_summary) AND NOT (SELECT excluded FROM checks)
   UNION SELECT 'MISSING_REQUIRED_FIELDS' WHERE (SELECT count>1 FROM candidate_summary)
 )
 SELECT jsonb_build_object(
   'verification_state','FETCHED','classification_status',CASE WHEN ch.excluded THEN 'NOT_APPLICABLE' WHEN cs.count=1 THEN 'CONFIRMED' ELSE 'REVIEW_REQUIRED' END,
   'resolver_version','fitmatch-provider-api-20260909-r1','policy_version',policy_value->>'version',
   'product_structure_code',CASE
      WHEN (SELECT component_count>1 AND contract_count>1 FROM component_summary) THEN 'SET'
      WHEN EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion' AND "values" ? 'UPPER_LOWER_SET') THEN 'SET'
      WHEN EXISTS(SELECT 1 FROM hits WHERE dimension='structure' AND "values" ? 'MULTIPACK') THEN 'MULTIPACK'
      ELSE 'UNKNOWN' END,
   'wearing_role',CASE WHEN (SELECT inner_context FROM context) THEN 'INNERWEAR' ELSE NULL END,
   'source_code',p_observation->>'source_code','source_product_key',p_observation->>'source_product_key',
   'input_fingerprint',fp.input_fingerprint,'policy_fingerprint',fp.policy_fingerprint,
   'candidate_set_hash',encode(sha256(convert_to(fp.input_fingerprint||'|'||fp.policy_fingerprint||'|'||cs.candidates::text,'UTF8')),'hex'),
   'reason_codes',(SELECT coalesce(jsonb_agg(code ORDER BY code),'[]'::jsonb) FROM reasons),
   'classification',CASE WHEN NOT ch.excluded AND cs.count=1 THEN cs.candidates->0 ELSE NULL END,
   'fixed_facts',CASE WHEN cs.count>0 THEN (SELECT coalesce(jsonb_object_agg(k,v),'{}'::jsonb) FROM common_candidate_fields) ELSE '{}'::jsonb END,
   'observed_partial_facts',(SELECT coalesce(jsonb_object_agg(dimension,value),'{}'::jsonb) FROM known),
   'unknown_fields',(SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb) FROM missing),
   'candidate_count',cs.count,'candidates',cs.candidates,
   'recovery_action',CASE WHEN ch.excluded THEN 'BLOCK_NOT_APPLICABLE' WHEN cs.count=1 THEN 'USE_RECOMMENDATION' WHEN cs.count>1 THEN 'SELECT_MISSING_FIELDS' ELSE 'ACQUIRE_EVIDENCE_OR_REVIEW_POLICY' END,
   'evidence',(SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY dimension,rule_id,source_path,value),'[]'::jsonb) FROM hits h),
   'classification_evidence_basis','API_REPORTED_FACTS',
   'measurement_evidence_summary',jsonb_build_object(
      'record_count',jsonb_array_length(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)),
      'garment_record_count',(SELECT count(*) FROM jsonb_array_elements(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)) m WHERE m->>'scope'='GARMENT'),
      'body_record_count',(SELECT count(*) FROM jsonb_array_elements(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)) m WHERE m->>'scope'='BODY'),
      'missing_unit_count',(SELECT count(*) FROM jsonb_array_elements(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)) m WHERE nullif(m->>'raw_unit','') IS NULL),
      'numeric_axis_inference','DISABLED_NO_VERIFIED_CALIBRATION',
      'fetch_state',p_observation#>>'{measurement_evidence,fetch_state}'),
   'comparison_authorized',false,'measurement_readiness','NOT_EVALUATED') INTO result
 FROM checks ch CROSS JOIN candidate_summary cs CROSS JOIN fingerprints fp;
 facts_result := result;
END;

   EXCEPTION WHEN SQLSTATE '22023' THEN
     -- Invalid OPTIONAL classification facts cannot invent authority or abort an
     -- otherwise valid retailer observation. They produce an explicit review block.
     invalid_evidence:=true;
   END;
 END IF;
 IF invalid_evidence THEN
   facts_result:=jsonb_build_object('classification_status','REVIEW_REQUIRED','candidates','[]'::jsonb,
       'candidate_count',0,'reason_codes',jsonb_build_array('INVALID_CURRENT_RETAILER_FACTS'),
       'input_fingerprint',encode(sha256(convert_to(coalesce(envelope,'{}'::jsonb)::text,'UTF8')),'hex'),
       'policy_fingerprint',encode(sha256(convert_to(policy_value::text,'UTF8')),'hex'));
 END IF;

 -- A verified exclusion is never relaxed. Explicit multiple measurement components
 -- are an exclusion even when a historical category mapping was DIRECT.
 IF base->>'classification_status'='NOT_APPLICABLE' THEN RETURN base; END IF;
 IF base->>'comparison_measurement_contract'='MULTIPLE_COMPONENT' THEN
   status_value:='NOT_APPLICABLE'; reason_value:='Multiple component measurement contracts';
 ELSIF facts_result->>'classification_status'='NOT_APPLICABLE' THEN
   status_value:='NOT_APPLICABLE'; reason_value:='Current retailer evidence excludes comparison';
 ELSE
   candidate_values:=coalesce(facts_result->'candidates','[]'::jsonb);
   SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(facts_result->'evidence','[]'::jsonb)) e
       WHERE e->>'field' IN ('name','attribute') AND e->>'dimension' IN
       ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code'))
   INTO product_specific;

   -- Disagreement with a complete verified tuple is a review conflict, never an
   -- automatic replacement. Agreement keeps the existing mapping UUID and version.
   IF base->>'classification_status'='CONFIRMED' THEN
     SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(facts_result->'evidence','[]'::jsonb)) e
       WHERE e->>'dimension' IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
         AND base->>(e->>'dimension') IS NOT NULL
         AND NOT (e->'values' ? (base->>(e->>'dimension')))) INTO conflict;
     conflict:=conflict OR invalid_evidence
        OR coalesce(facts_result->'reason_codes','[]'::jsonb) ?|
           ARRAY['BUNDLE_CONTENTS_UNPROVEN','UNSUPPORTED_GARMENT_TYPE','UNSUPPORTED_RETAILER_AXIS',
                 'TYPE_EVIDENCE_CONFLICT','MISSING_OR_CONFLICTING_AUDIENCE'];
     IF NOT conflict THEN RETURN base; END IF;
     candidate_values:='[]'::jsonb;
     reason_value:='Current retailer facts conflict with verified mapping authority';
   ELSIF base->>'reason' IN ('Equal-top candidates have different outcomes','DIRECT classification tuple is invalid')
     AND NOT (
       base->>'resolution_mode'='CANDIDATE'
       AND NOT EXISTS (
         SELECT 1 FROM fitmatch_vnext.product_classification_signals pcs
         JOIN fitmatch_vnext.source_classification_signals s ON s.id=pcs.source_signal_id AND s.is_active
         JOIN fitmatch_vnext.classification_signal_mappings m ON m.source_signal_id=s.id AND m.is_active AND m.is_verified
         WHERE pcs.product_id=product_row.id AND s.source_code=product_row.source_code
           AND m.audience_code IN ('ANY',product_row.audience_code)
           AND s.signal_kind=(SELECT signal_kind FROM fitmatch_vnext.source_classification_signals
               WHERE id=(base->>'primary_source_signal_id')::uuid)
           AND m.priority=(SELECT priority FROM fitmatch_vnext.classification_signal_mappings WHERE id=(base->>'mapping_id')::uuid)
           AND (m.resolution_mode<>'CANDIDATE' OR s.id<>(base->>'primary_source_signal_id')::uuid)
       )
     ) THEN
     conflict:=true; candidate_values:='[]'::jsonb;
     reason_value:='Existing mapping authority conflict requires remediation';
   END IF;

   -- Explicit CANDIDATE authority is a bound, not a vocabulary hint. Current facts
   -- can narrow it; they cannot introduce a tuple outside the verified candidate set.
   IF NOT conflict AND base->>'resolution_mode'='CANDIDATE' THEN
     SELECT coalesce(jsonb_agg(c ORDER BY c::text),'[]'::jsonb) INTO candidate_values
     FROM jsonb_array_elements(candidate_values) c
     WHERE EXISTS(SELECT 1 FROM fitmatch_vnext.classification_signal_mappings m
       WHERE m.source_signal_id=(base->>'primary_source_signal_id')::uuid
         AND m.is_active AND m.is_verified AND m.resolution_mode='CANDIDATE'
         AND m.priority=(SELECT priority FROM fitmatch_vnext.classification_signal_mappings WHERE id=(base->>'mapping_id')::uuid)
         AND m.audience_code IN ('ANY',product_row.audience_code)
         AND (m.audience_code=product_row.audience_code OR NOT EXISTS (
           SELECT 1 FROM fitmatch_vnext.classification_signal_mappings exact_m
           WHERE exact_m.source_signal_id=m.source_signal_id AND exact_m.is_active AND exact_m.is_verified
             AND exact_m.resolution_mode='CANDIDATE' AND exact_m.priority=m.priority
             AND exact_m.audience_code=product_row.audience_code))
         AND m.garment_type_code=c->>'garment_type_code'
         AND m.sleeve_length_code IS NOT DISTINCT FROM c->>'sleeve_length_code'
         AND m.lower_length_code IS NOT DISTINCT FROM c->>'lower_length_code'
         AND m.body_length_code IS NOT DISTINCT FROM c->>'body_length_code');
   END IF;
   -- Candidate construction uses the active garment's uses_* axes and verified
   -- axis values; SET was excluded above. It already satisfies the pinned deployed
   -- tuple validator, which is additionally exercised by the integration harness
   -- and existing product/override triggers. Do not add a new privileged call to
   -- this existing SECURITY INVOKER reader.

   -- Match the existing recovery writer's bound without truncating candidates.
   IF jsonb_array_length(candidate_values)>64 THEN
     candidate_values:='[]'::jsonb;
     reason_value:='Canonical candidate space exceeds the recovery contract bound';
     facts_result:=facts_result||jsonb_build_object('reason_codes',coalesce(facts_result->'reason_codes','[]'::jsonb)||jsonb_build_array('CANDIDATE_SPACE_TOO_BROAD'));
   END IF;
   status_value:=CASE WHEN NOT conflict AND NOT invalid_evidence
       AND facts_result->>'classification_status'='CONFIRMED'
       AND jsonb_array_length(candidate_values)=1
       AND (base->>'resolution_mode' IS DISTINCT FROM 'PRODUCT_REQUIRED' OR product_specific)
       THEN 'CONFIRMED' ELSE 'REVIEW_REQUIRED' END;
   reason_value:=coalesce(reason_value,CASE WHEN status_value='CONFIRMED'
       THEN 'Complete current product-scoped retailer evidence'
       ELSE 'Current retailer facts require explicit completion or additional evidence' END);
 END IF;
 IF status_value='NOT_APPLICABLE' THEN candidate_values:='[]'::jsonb; END IF;
 tuple_value:=CASE WHEN status_value='CONFIRMED' THEN candidate_values->0 ELSE '{}'::jsonb END;
 -- Return a coherent bounded decision, not a stale hash/status from the broader
 -- intermediate vocabulary proposal. Observed partial facts remain diagnostic.
 SELECT coalesce(jsonb_object_agg(k,v),'{}'::jsonb) INTO fixed_value
 FROM (SELECT k,jsonb_agg(DISTINCT v)->0 v FROM jsonb_array_elements(candidate_values) c
       CROSS JOIN LATERAL jsonb_each(c) e(k,v)
       GROUP BY k HAVING count(DISTINCT v)=1 AND jsonb_agg(DISTINCT v)->0<>'null'::jsonb) common;
 SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb) INTO unknown_value
 FROM (SELECT k FROM jsonb_array_elements(candidate_values) c CROSS JOIN LATERAL jsonb_each(c) e(k,v)
       WHERE k IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
       GROUP BY k HAVING count(DISTINCT v)>1) missing;
 facts_result:=facts_result||jsonb_build_object('fact_proposal_status',facts_result->>'classification_status',
     'classification_status',status_value,'classification',CASE WHEN status_value='CONFIRMED' THEN tuple_value ELSE NULL END,
     'candidates',candidate_values,'candidate_count',jsonb_array_length(candidate_values),'authority_conflict',conflict,
     'fixed_facts',fixed_value,'unknown_fields',unknown_value,
     'candidate_set_hash',encode(sha256(convert_to(jsonb_build_object('facts_input',facts_result->>'input_fingerprint',
         'facts_policy',facts_result->>'policy_fingerprint','authority',base,'candidates',candidate_values)::text,'UTF8')),'hex'),
     'recovery_action',CASE WHEN status_value='NOT_APPLICABLE' THEN 'BLOCK_NOT_APPLICABLE'
         WHEN status_value='CONFIRMED' THEN 'USE_RECOMMENDATION'
         WHEN jsonb_array_length(candidate_values)>0 THEN 'SELECT_MISSING_FIELDS' ELSE 'ACQUIRE_EVIDENCE_OR_REVIEW_POLICY' END);
 RETURN jsonb_strip_nulls(jsonb_build_object('found',true,'product_id',product_row.id,
   'source_code',product_row.source_code,'source_product_key',product_row.source_product_key,
   'classification_status',status_value,'resolution_mode',CASE status_value
       WHEN 'CONFIRMED' THEN 'DIRECT' WHEN 'NOT_APPLICABLE' THEN 'NOT_APPLICABLE' ELSE 'REVIEW_REQUIRED' END,
   'garment_type_code',tuple_value->>'garment_type_code','sleeve_length_code',tuple_value->>'sleeve_length_code',
   'lower_length_code',tuple_value->>'lower_length_code','body_length_code',tuple_value->>'body_length_code',
   'audience_code',product_row.audience_code,'product_structure_code',product_row.product_structure_code,
   'comparison_measurement_contract',base->>'comparison_measurement_contract',
   'comparison_unit_eligible',CASE WHEN status_value='NOT_APPLICABLE' THEN 'false'::jsonb ELSE base->'comparison_unit_eligible' END,
   'reason',reason_value,'resolver_version',version_value,
   'input_fingerprint',encode(sha256(convert_to(jsonb_build_object('baseline',base,
       'facts_input',facts_result->>'input_fingerprint','facts_policy',facts_result->>'policy_fingerprint',
       'candidates',candidate_values,'status',status_value,'version',version_value)::text,'UTF8')),'hex')))
   || jsonb_build_object('retailer_fact_decision',facts_result,'mapping_authority_snapshot',base);
END;

 END IF;
 -- v1 was already applied. Keep its complete algorithm for rows last classified
 -- with v1, including live authority freshness checks and personal-choice hashes.
 -- A fresh accepted observation clears resolver_version and enters v2 below.
 IF EXISTS(SELECT 1 FROM fitmatch_vnext.products
     WHERE source_code=p_source_code AND source_product_key=p_source_product_key
       AND resolver_version='fitmatch-vnext-current-retailer-facts-20260909-v1') THEN
   
DECLARE
 base jsonb; product_row fitmatch_vnext.products%rowtype;
 p_observation jsonb; fact_array jsonb; envelope jsonb; facts_result jsonb;
 policy_value constant jsonb := $policy${"version":"fitmatch-evidence-policy-2026-v1","rules":[{"rule_id":"scope.upper","dimension":"garment_type_code","values":["sleeveless_tshirt","tshirt","tank_top","sweatshirt","knit_sweater","shirt_blouse","polo_shirt","hoodie","cardigan","knit_vest","base_layer_top","sports_top","bodysuit_top","zip_hoodie","homewear_top"],"pattern":"^(상의|TOPS)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"scope.pants","dimension":"garment_type_code","values":["denim_pants","slacks_trousers","chino_cotton_pants","cargo_pants","casual_pants","shorts","sweat_jogger_pants","other_standard_pants","leggings","homewear_bottom"],"pattern":"^(바지|팬츠|하의|기타 바지|PANTS|TROUSERS|PANTALON)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"scope.inner","dimension":"garment_type_code","values":["base_layer_top","men_undershirt","women_camisole","women_bra","men_briefs","men_trunks","women_panty","women_slip"],"pattern":"^(이너웨어|언더웨어|UNDERWEAR|INNERWEAR|INNER TOPS|이너웨어 상의)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.tshirt","dimension":"garment_type_code","values":["tshirt"],"pattern":"(티셔츠|반팔티|긴팔티|그래픽T|크루넥T|U넥T|V넥T|\\mtee\\M|\\mt[ -]?shirt[s]?\\M)","fields":["category","name"],"unless_pattern":"(폴로|카라|니트|KNIT|민소매|슬리브리스|sleeveless|원피스|dress|셔츠\\s*&|후리스)","context":"OUTER_CONTEXT"},{"rule_id":"type.base_layer","dimension":"garment_type_code","values":["base_layer_top"],"pattern":"(티셔츠|크루넥T|U넥T|V넥T|이너웨어 상의|INNER TOPS|undershirt|base.layer top)","fields":["category","name"],"unless_pattern":"(원피스|드레스)","context":"INNER_CONTEXT"},{"rule_id":"type.sleeveless_tee","dimension":"garment_type_code","values":["sleeveless_tshirt"],"pattern":"(민소매 티셔츠|슬리브리스 티셔츠|sleeveless t.shirt)","fields":["category","name"],"unless_pattern":"(원피스|dress)","context":"OUTER_CONTEXT"},{"rule_id":"type.tank","dimension":"garment_type_code","values":["tank_top"],"pattern":"(탱크[톱탑]|tank top|싱글렛|singlet)","fields":["category","name"],"unless_pattern":"(원피스|dress)","context":"OUTER_CONTEXT"},{"rule_id":"type.shirt.name","dimension":"garment_type_code","values":["shirt_blouse"],"pattern":"(셔츠|블라우스|\\mshirts?\\M|\\mblouses?\\M)","fields":["name"],"unless_pattern":"(티셔츠|폴로|카라|스웨트[ ]?셔츠|맨투맨|t.shirt|sweatshirt|polo|원피스|dress|오버셔츠|overshirt|파자마|이너웨어|셔츠\\s*&|후리스)","context":"ANY"},{"rule_id":"type.shirt.category","dimension":"garment_type_code","values":["shirt_blouse"],"pattern":"(셔츠|블라우스|\\mshirts?\\M|\\mblouses?\\M)","fields":["category"],"unless_pattern":"(티셔츠|폴로|카라|스웨트[ ]?셔츠|맨투맨|t.shirt|sweatshirt|polo|원피스|dress|오버셔츠|overshirt|파자마|이너웨어|셔츠\\s*&|후리스)|^셔츠$","context":"ANY"},{"rule_id":"type.polo","dimension":"garment_type_code","values":["polo_shirt"],"pattern":"(폴로셔츠|카라[ ]?티|피케.?티셔츠|\\mpolo\\M)","fields":["category","name"],"unless_pattern":"(니트|knit|원피스|dress)","context":"ANY"},{"rule_id":"type.knit","dimension":"garment_type_code","values":["knit_sweater"],"pattern":"(니트|스웨터|\\mknit\\M|sweater|jumper)","fields":["category","name"],"unless_pattern":"(가디건|카디건|cardigan|베스트|vest|원피스|dress|팬츠|pants|스커트|skirt|가디건\\s*&|니트\\s*/|스웨터\\s*\\|)","context":"ANY"},{"rule_id":"type.cardigan","dimension":"garment_type_code","values":["cardigan"],"pattern":"(가디건|카디건|cardigan)","fields":["category","name"],"unless_pattern":"(니트 & 가디건|스웨터.*\\||sweaters? \\|)","context":"ANY"},{"rule_id":"type.knit_vest","dimension":"garment_type_code","values":["knit_vest"],"pattern":"(니트[ ]?베스트|knit vest)","fields":["category","name"],"unless_pattern":"(원피스|dress)","context":"ANY"},{"rule_id":"type.sweatshirt","dimension":"garment_type_code","values":["sweatshirt"],"pattern":"(맨투맨|스웨트[ ]?셔츠|sweatshirt)","fields":["category","name"],"unless_pattern":"(후드|hood|후리스|스웨트셔츠\\s*&|스웨트셔츠\\s*\\|)","context":"ANY"},{"rule_id":"type.hoodie","dimension":"garment_type_code","values":["hoodie"],"pattern":"(후드[ ]?티|후드티셔츠|\\mhoodie\\M)","fields":["category","name"],"unless_pattern":"(집업|zip|재킷|자켓|jacket|바람막이)","context":"ANY"},{"rule_id":"type.zip_hoodie","dimension":"garment_type_code","values":["zip_hoodie"],"pattern":"(후드[ ]?집업|스웨트풀집|zip.up hoodie)","fields":["category","name"],"unless_pattern":"(후리스|fleece|바람막이)","context":"ANY"},{"rule_id":"type.denim","dimension":"garment_type_code","values":["denim_pants"],"pattern":"(데님[ ]?팬츠|청바지|청/데님 팬츠|\\mjeans\\M|denim pants)","fields":["category","name"],"unless_pattern":"(재킷|셔츠|스커트|jacket|shirt|skirt)","context":"ANY"},{"rule_id":"type.slacks","dimension":"garment_type_code","values":["slacks_trousers"],"pattern":"(슬랙스|sastrería pant|tailored trousers)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.chino","dimension":"garment_type_code","values":["chino_cotton_pants"],"pattern":"(치노|코튼 팬츠|chino)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.cargo","dimension":"garment_type_code","values":["cargo_pants"],"pattern":"(카고|유틸리티팬츠|cargo|utility pants|crg pnt)","fields":["category","name"],"unless_pattern":"(재킷|jacket)","context":"ANY"},{"rule_id":"type.jogger","dimension":"garment_type_code","values":["sweat_jogger_pants"],"pattern":"(조거[ ]?팬츠|스웨트[ ]?팬츠|트레이닝[ /]?조거 팬츠|jogger|sweatpants)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.shorts","dimension":"garment_type_code","values":["shorts"],"pattern":"(반바지|쇼트팬츠|쇼트 팬츠|숏[ ]?팬츠|쇼츠|버뮤다|\\mshorts\\M|bermuda)","fields":["category","name"],"unless_pattern":"(데님|청바지|denim|카고|cargo|코튼저지|팬티|brief|trunk)","context":"OUTER_CONTEXT"},{"rule_id":"type.leggings","dimension":"garment_type_code","values":["leggings"],"pattern":"(레깅스|leggings)","fields":["category","name"],"unless_pattern":"(레깅스 & 팬츠)","context":"ANY"},{"rule_id":"type.skirt","dimension":"garment_type_code","values":["skirt"],"pattern":"(스커트|치마|\\mskirt[s]?\\M)","fields":["category","name"],"unless_pattern":"(원피스.*스커트|스커트.*원피스|원피스|스커트 팬츠)","context":"ANY"},{"rule_id":"type.dress","dimension":"garment_type_code","values":["dress"],"pattern":"(원피스|드레스|\\mdresses?\\M|\\mdress\\M)","fields":["category","name"],"unless_pattern":"(원피스.*스커트|스커트.*원피스)","context":"ANY"},{"rule_id":"type.blazer","dimension":"garment_type_code","values":["blazer"],"pattern":"(블레이저|브레이저|blazer)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.trench","dimension":"garment_type_code","values":["trench_coat"],"pattern":"(트렌치[ ]?코트|trench coat)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.coat","dimension":"garment_type_code","values":["coat"],"pattern":"(코트|\\mcoat\\M)","fields":["category","name"],"unless_pattern":"(트렌치|trench|재킷 & 코트)","context":"ANY"},{"rule_id":"type.ma1","dimension":"garment_type_code","values":["ma1"],"pattern":"(MA-1|항공점퍼)","fields":["category","name"],"unless_pattern":"(블루종/MA-1)","context":"ANY"},{"rule_id":"type.blouson","dimension":"garment_type_code","values":["blouson"],"pattern":"(블루종|blouson)","fields":["category","name"],"unless_pattern":"(블루종/MA-1|파카 & 블루종)","context":"ANY"},{"rule_id":"type.windbreaker","dimension":"garment_type_code","values":["windbreaker"],"pattern":"(바람막이|windbreaker)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.anorak","dimension":"garment_type_code","values":["anorak"],"pattern":"(아노락|anorak)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.fleece","dimension":"garment_type_code","values":["fleece_jacket"],"pattern":"(플리스[ ]?재킷|후리스[ ]?재킷|fleece jacket)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.puffer","dimension":"garment_type_code","values":["puffer_jacket"],"pattern":"(다운[ ]?재킷|패딩[ ]?재킷|다운[ ]?자켓|puffer jacket)","fields":["category","name"],"unless_pattern":"(조끼|vest)","context":"ANY"},{"rule_id":"type.puffer_vest","dimension":"garment_type_code","values":["puffer_vest"],"pattern":"(패딩[ ]?조끼|다운[ ]?베스트|puffer vest)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.mouton","dimension":"garment_type_code","values":["mouton"],"pattern":"(무스탕|mouton)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.bra","dimension":"garment_type_code","values":["women_bra"],"pattern":"^(브라|와이어리스 브라)$","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.briefs","dimension":"garment_type_code","values":["men_briefs"],"pattern":"(복서브리프|boxer briefs)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.trunks","dimension":"garment_type_code","values":["men_trunks"],"pattern":"(트렁크|trunks)","fields":["category","name"],"unless_pattern":"","context":"INNER_CONTEXT"},{"rule_id":"type.panty","dimension":"garment_type_code","values":["women_panty"],"pattern":"(여성 팬티|women.s panties)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.camisole","dimension":"garment_type_code","values":["women_camisole"],"pattern":"(캐미솔|camisole)","fields":["category","name"],"unless_pattern":"(원피스|dress)","context":"INNER_CONTEXT"},{"rule_id":"scope.shirt_family","dimension":"garment_type_code","values":["shirt_blouse","polo_shirt"],"pattern":"^셔츠$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"scope.vest","dimension":"garment_type_code","values":["outer_vest","knit_vest","puffer_vest"],"pattern":"^(조끼|베스트)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.structured_knit_vest","dimension":"garment_type_code","values":["knit_vest"],"pattern":"^KNIT VEST$","fields":["subfamily"],"unless_pattern":"","context":"ANY"},{"rule_id":"type.structured_knit_sweater","dimension":"garment_type_code","values":["knit_sweater"],"pattern":"^KNIT SWEATER$","fields":["subfamily"],"unless_pattern":"","context":"ANY"},{"rule_id":"scope.jacket","dimension":"garment_type_code","values":["jacket","blouson","blazer","ma1","windbreaker","anorak","fleece_jacket","puffer_jacket","mouton"],"pattern":"(재킷|자켓|\\mjacket\\M|F. Cazadora)","fields":["category","name"],"unless_pattern":"(재킷 &|나일론/코치|점퍼/재킷)","context":"ANY"},{"rule_id":"unsupported.jumpsuit","dimension":"unsupported_type","values":["jumpsuit"],"pattern":"(점프수트|jumpsuit)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"unsupported.skorts","dimension":"unsupported_type","values":["skorts"],"pattern":"(스코츠|스커트 팬츠|\\mskorts?\\M)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"exclude.non_apparel","dimension":"exclusion","values":["NON_APPAREL"],"pattern":"^(가방|모자|벨트|선글라스|우산|장갑|신발|슈즈|향수|액세서리|BAG|SHOES|PERFUME|ACCESSORIES|BAGS)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"exclude.upper_lower_set","dimension":"exclusion","values":["UPPER_LOWER_SET"],"pattern":"(상[ ]?하의[ ]?세트|상의.*하의.*세트|셔츠.*팬츠.*세트|top and (pants|trousers) set)","fields":["category","name"],"unless_pattern":"","context":"ANY"},{"rule_id":"structure.set_ambiguous","dimension":"structure","values":["AMBIGUOUS_BUNDLE"],"pattern":"(세트|\\mset\\M)","fields":["name"],"unless_pattern":"(셋업|set.up|세트.*별도|별도.*세트)","context":"ANY"},{"rule_id":"structure.multipack","dimension":"structure","values":["MULTIPACK"],"pattern":"([2-9][ ]?(팩|P\\M)|multipack|[2-9].pack)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.name.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"(반팔|반소매|쇼트 슬리브|short[ -]sleeve)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.desc.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"(반팔|반소매|쇼트 슬리브|short[ -]sleeve)","fields":["description"],"unless_pattern":"(함께|매치|스타일링|코디|아닌|아니라|않|처럼|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"sleeve.name.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"(긴팔|긴소매|롱 슬리브|long[ -]sleeve)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.desc.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"(긴팔|긴소매|롱 슬리브|long[ -]sleeve)","fields":["description"],"unless_pattern":"(함께|매치|스타일링|코디|아닌|아니라|않|처럼|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"sleeve.name.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"(민소매|슬리브리스|sleeveless|탱크[탑톱]|캐미솔)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.desc.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"(민소매|슬리브리스|sleeveless|탱크[탑톱]|캐미솔)","fields":["description"],"unless_pattern":"(함께|매치|스타일링|코디|아닌|아니라|않|처럼|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"sleeve.name.three_quarter_sleeve","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"(7부[ ]?소매|three.quarter[ -]sleeve)","fields":["name"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.desc.three_quarter_sleeve","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"(7부[ ]?소매|three.quarter[ -]sleeve)","fields":["description"],"unless_pattern":"(함께|매치|스타일링|코디|아닌|아니라|않|처럼|without|pair with|not |스타일로)","context":"ANY"},{"rule_id":"sleeve.category.short_sleeve","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"^(반팔|반소매|반소매 티셔츠|short sleeve)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.category.long_sleeve","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"^(긴팔|긴소매|긴소매 티셔츠|long sleeve)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.category.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"^(슬리브리스|민소매 티셔츠|캐미솔|탱크탑)$","fields":["category"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.attribute.short","dimension":"sleeve_length_code","values":["short_sleeve"],"pattern":"^sleeve=short$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.attribute.long","dimension":"sleeve_length_code","values":["long_sleeve"],"pattern":"^sleeve=long$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.attribute.sleeveless","dimension":"sleeve_length_code","values":["sleeveless"],"pattern":"^sleeve=sleeveless$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"sleeve.attribute.three-quarter","dimension":"sleeve_length_code","values":["three_quarter_sleeve"],"pattern":"^sleeve=three-quarter$","fields":["attribute"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.short_length","dimension":"lower_length_code","values":["short_length"],"pattern":"(반바지|쇼트팬츠|쇼트 팬츠|숏[ ]?팬츠|쇼츠|버뮤다|\\mshorts\\M|bermuda)","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.cropped_length","dimension":"lower_length_code","values":["cropped_length"],"pattern":"(크롭[ ]?(팬츠|진)|cropped (pants|jeans|trousers))","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.ankle_length","dimension":"lower_length_code","values":["ankle_length"],"pattern":"(앵클[ ]?팬츠|ankle.length)","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.long_length","dimension":"lower_length_code","values":["long_length"],"pattern":"(롱[ ]?팬츠|긴바지|full.length|long trousers|long pants)","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"lower.three_quarter_length","dimension":"lower_length_code","values":["three_quarter_length"],"pattern":"(7부[ ]?(팬츠|바지)|three.quarter trousers)","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"body.short_body","dimension":"body_length_code","values":["short_body"],"pattern":"(미니( [^ .]+){0,3}[ ]?(원피스|스커트)|mini (dress|skirt)|숏[ ]?(코트|패딩))","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"body.description.short_body","dimension":"body_length_code","values":["short_body"],"pattern":"(미니( [^ .]+){0,3}[ ]?(원피스|스커트)|mini (dress|skirt)|숏[ ]?(코트|패딩))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아닌|아니라|않|처럼|without|pair with|not )","context":"ANY"},{"rule_id":"body.medium_body","dimension":"body_length_code","values":["medium_body"],"pattern":"(미디( [^ .]+){0,3}[ ]?(원피스|스커트)|midi (dress|skirt))","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"body.description.medium_body","dimension":"body_length_code","values":["medium_body"],"pattern":"(미디( [^ .]+){0,3}[ ]?(원피스|스커트)|midi (dress|skirt))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아닌|아니라|않|처럼|without|pair with|not )","context":"ANY"},{"rule_id":"body.long_body","dimension":"body_length_code","values":["long_body"],"pattern":"(롱[ ]?(원피스|스커트|코트)|맥시[ ]?(원피스|스커트)|long (dress|skirt|coat)|maxi (dress|skirt))","fields":["name","category"],"unless_pattern":"","context":"ANY"},{"rule_id":"body.description.long_body","dimension":"body_length_code","values":["long_body"],"pattern":"(롱[ ]?(원피스|스커트|코트)|맥시[ ]?(원피스|스커트)|long (dress|skirt|coat)|maxi (dress|skirt))","fields":["description"],"unless_pattern":"(함께|매치|코디|스타일링|아닌|아니라|않|처럼|without|pair with|not )","context":"ANY"}]}$policy$::jsonb;
 version_value constant text := 'fitmatch-vnext-current-retailer-facts-20260909-v1';
 status_value text; reason_value text; candidate_values jsonb := '[]'::jsonb;
 tuple_value jsonb; fixed_value jsonb; unknown_value jsonb;
 conflict boolean := false; product_specific boolean := false; invalid_evidence boolean := false;
BEGIN
 -- The deployed verified-mapping algorithm is retained verbatim as the first authority.
 SELECT old_decision.value INTO base FROM (with recursive product_row as (
    select p.*
    from fitmatch_vnext.products p
    where p.source_code = p_source_code
      and p.source_product_key = p_source_product_key
),

comparison_unit as (
    select
        p.id,
        fitmatch_vnext.product_comparison_unit_decision(p.id) unit
    from product_row p
),

evidence as (
    select
        p.id product_id,
        pcs.source_signal_id,
        pcs.evidence_order,
        ss.signal_kind,
        ss.external_key,

        case ss.signal_kind
            when 'PRODUCT_EXACT' then 600
            when 'PRODUCT_STRUCTURE' then 500
            when 'PRODUCT_TYPE' then 400
            when 'SUBFAMILY' then 300
            when 'FAMILY' then 250
            when 'CATEGORY' then 200
            when 'SECTION' then 150
            else 100
        end evidence_rank

    from product_row p

    join fitmatch_vnext.product_classification_signals pcs
      on pcs.product_id = p.id

    join fitmatch_vnext.source_classification_signals ss
      on ss.id = pcs.source_signal_id
     and ss.source_code = p.source_code
     and ss.is_active
),

raw_candidates as (
    select
        e.*,
        m.id mapping_id,
        m.resolution_mode,
        m.garment_type_code,
        m.sleeve_length_code,
        m.lower_length_code,
        m.body_length_code,
        m.priority,
        m.mapping_version,
        m.mapping_checksum

    from evidence e

    join product_row p
      on p.id = e.product_id

    join fitmatch_vnext.classification_signal_mappings m
      on m.source_signal_id = e.source_signal_id
     and m.is_active
     and m.is_verified
     and (
         m.audience_code = 'ANY'
         or m.audience_code = p.audience_code
     )
     and (
         coalesce(m.mapping_version, '')
            <> 'vnext-uniqlo-complete-path-20260902-v3'
         or fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current(m.id)
     )
),

signal_ancestry(
    descendant_id,
    ancestor_id,
    depth
) as (
    select
        s.id,
        s.parent_signal_id,
        1
    from fitmatch_vnext.source_classification_signals s
    where s.parent_signal_id is not null

    union all

    select
        a.descendant_id,
        s.parent_signal_id,
        a.depth + 1

    from signal_ancestry a

    join fitmatch_vnext.source_classification_signals s
      on s.id = a.ancestor_id

    where s.parent_signal_id is not null
      and a.depth < 16
),

candidates as (
    select
        c.*,
        max(c.evidence_rank) over () max_evidence_rank

    from raw_candidates c

    where not exists (
        select 1
        from raw_candidates d

        join signal_ancestry a
          on a.descendant_id = d.source_signal_id
         and a.ancestor_id = c.source_signal_id

        where d.product_id = c.product_id
          and c.resolution_mode = 'PRODUCT_REQUIRED'
          and d.resolution_mode = 'DIRECT'
          and d.evidence_rank = c.evidence_rank
          and d.priority = c.priority
    )
),

ranked as (
    select
        c.*,
        max(priority) over () max_priority

    from candidates c

    where evidence_rank = max_evidence_rank
),

top_candidates as (
    select *
    from ranked
    where priority = max_priority
),

summary as (
    select
        count(*) candidate_count,

        count(
            distinct concat_ws(
                '|',
                resolution_mode,
                coalesce(garment_type_code, '∅'),
                coalesce(sleeve_length_code, '∅'),
                coalesce(lower_length_code, '∅'),
                coalesce(body_length_code, '∅')
            )
        ) outcome_count

    from top_candidates
),

chosen as (
    select *
    from top_candidates

    order by
        case
            when lower(p_source_code) = 'uniqlo'
             and signal_kind = 'CATEGORY'
            then evidence_order
        end desc nulls last,

        evidence_order,
        source_signal_id,
        mapping_id

    limit 1
),

resolved as (
    select
        p.*,
        unit.unit comparison_unit,

        c.source_signal_id,
        c.mapping_id,
        c.resolution_mode mapping_resolution_mode,

        c.garment_type_code mapped_garment_type_code,
        c.sleeve_length_code mapped_sleeve_length_code,
        c.lower_length_code mapped_lower_length_code,
        c.body_length_code mapped_body_length_code,

        c.mapping_version,
        c.mapping_checksum,

        coalesce(s.candidate_count, 0) candidate_count,
        coalesce(s.outcome_count, 0) outcome_count

    from product_row p

    left join comparison_unit unit
      on unit.id = p.id

    left join summary s
      on true

    left join chosen c
      on true
),

decision as (
    select
        r.*,

        case
            when upper(coalesce(r.product_structure_code, 'UNKNOWN')) = 'SET'
                then 'NOT_APPLICABLE'

            when r.candidate_count = 0
                then 'REVIEW_REQUIRED'

            when r.outcome_count > 1
                then 'REVIEW_REQUIRED'

            when r.mapping_resolution_mode = 'NOT_APPLICABLE'
                then 'NOT_APPLICABLE'

            when r.mapping_resolution_mode = 'DIRECT'
             and coalesce(
                (
                    fitmatch_vnext.classification_tuple_validation(
                        r.mapped_garment_type_code,
                        r.product_structure_code,
                        r.audience_code,
                        r.mapped_sleeve_length_code,
                        r.mapped_lower_length_code,
                        r.mapped_body_length_code
                    ) ->> 'valid'
                )::boolean,
                false
             )
                then 'CONFIRMED'

            else 'REVIEW_REQUIRED'
        end decision_status,

        case
            when upper(coalesce(r.product_structure_code, 'UNKNOWN')) = 'SET'
                then 'Product structure is SET'

            when r.candidate_count = 0
                then 'No active verified mapping candidate'

            when r.outcome_count > 1
                then 'Equal-top candidates have different outcomes'

            when r.mapping_resolution_mode = 'NOT_APPLICABLE'
                then 'Mapping is NOT_APPLICABLE'

            when r.mapping_resolution_mode = 'DIRECT'
             and coalesce(
                (
                    fitmatch_vnext.classification_tuple_validation(
                        r.mapped_garment_type_code,
                        r.product_structure_code,
                        r.audience_code,
                        r.mapped_sleeve_length_code,
                        r.mapped_lower_length_code,
                        r.mapped_body_length_code
                    ) ->> 'valid'
                )::boolean,
                false
             )
                then 'Complete verified DIRECT classification mapping'

            when r.mapping_resolution_mode = 'DIRECT'
                then 'DIRECT classification tuple is invalid'

            when r.mapping_resolution_mode = 'PRODUCT_REQUIRED'
                then 'Product-exact verified evidence is required'

            else 'Mapping requires review'
        end decision_reason

    from resolved r
)

select case

    when not exists (
        select 1 from product_row
    )
    then jsonb_build_object(
        'found', false,
        'classification_status', 'REVIEW_REQUIRED',
        'resolution_mode', 'REVIEW_REQUIRED',
        'reason', 'Unknown source product identity',
        'resolver_version',
            'fitmatch-vnext-resolver-v4-classification-only-uniqlo-deepest-category'
    )

    else (
        select jsonb_strip_nulls(
            jsonb_build_object(
                'found', true,
                'product_id', d.id,
                'source_code', d.source_code,
                'source_product_key', d.source_product_key,

                'classification_status', d.decision_status,

                'resolution_mode',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then 'DIRECT'
                        when d.decision_status = 'NOT_APPLICABLE'
                            then 'NOT_APPLICABLE'
                        else coalesce(
                            d.mapping_resolution_mode,
                            'REVIEW_REQUIRED'
                        )
                    end,

                'garment_type_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_garment_type_code
                    end,

                'product_structure_code',
                    d.product_structure_code,

                'comparison_measurement_contract',
                    d.comparison_unit ->> 'measurement_contract',

                'comparison_unit_eligible',
                    d.comparison_unit -> 'eligible',

                'audience_code',
                    d.audience_code,

                'sleeve_length_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_sleeve_length_code
                    end,

                'lower_length_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_lower_length_code
                    end,

                'body_length_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_body_length_code
                    end,

                'primary_source_signal_id',
                    d.source_signal_id,

                'mapping_id',
                    d.mapping_id,

                'mapping_version',
                    d.mapping_version,

                'mapping_checksum',
                    d.mapping_checksum,

                'reason',
                    d.decision_reason,

                'resolver_version',
                    'fitmatch-vnext-resolver-v4-classification-only-uniqlo-deepest-category',

                'input_fingerprint',
                    encode(
                        extensions.digest(
                            concat_ws(
                                '|',
                                d.source_code,
                                d.source_product_key,
                                d.audience_code,
                                d.product_structure_code,
                                coalesce(
                                    d.source_signal_id::text,
                                    '∅'
                                ),
                                coalesce(
                                    d.mapping_checksum,
                                    '∅'
                                ),
                                'fitmatch-vnext-resolver-v4-classification-only-uniqlo-deepest-category'
                            ),
                            'sha256'
                        ),
                        'hex'
                    )
            )
        )

        from decision d
    )

end) old_decision(value);
 IF NOT coalesce((base->>'found')::boolean,false) THEN RETURN base; END IF;
 SELECT * INTO product_row FROM fitmatch_vnext.products WHERE id=(base->>'product_id')::uuid;

 -- Installing this function cannot invalidate existing personal choices or reclassify
 -- stored rows. Existing ingress clears resolver_version only for a NEW observation.
 IF product_row.resolver_version IS NOT NULL AND product_row.resolver_version<>version_value
 THEN RETURN base; END IF;
 IF product_row.source_code NOT IN ('uniqlo','musinsa','zara') THEN RETURN base; END IF;

 -- Existing service-only ingress atomically writes these CURRENT projection fields
 -- and the immutable receipt. Read the public product projection, not the private
 -- receipt table: this existing SECURITY INVOKER reader retains its original grants.
 -- Never use _legacy_source_category_path or carried-forward migration metadata.
 IF coalesce(product_row.source_extra->>'latest_ingestion_fingerprint','') !~ '^[0-9a-f]{64}$'
    OR (product_row.source_extra->>'latest_ingestion_observed_at')::timestamptz
         IS DISTINCT FROM product_row.last_fetched_at
    OR product_row.last_fetched_at IS NULL
 THEN RETURN base; END IF;

 -- Existing service-role ingress already stores these provider facts. The optional
 -- observation supplies additional product attributes, without changing the RPC shape.
 envelope:=product_row.source_extra#>'{structured_facts,classification_observation}';
 IF envelope IS NOT NULL THEN
   IF jsonb_typeof(envelope) IS DISTINCT FROM 'object'
      OR envelope->>'contract_version' IS DISTINCT FROM 'retailer-facts-2026-v1'
      OR envelope->>'source_code' IS DISTINCT FROM product_row.source_code
      OR envelope->>'source_product_key' IS DISTINCT FROM product_row.source_product_key
      OR envelope->>'fetch_state' IS DISTINCT FROM 'FETCHED'
      OR envelope->'identity_verified' IS DISTINCT FROM 'true'::jsonb
   THEN invalid_evidence:=true;
   ELSE p_observation:=envelope;
   END IF;
 ELSE
   SELECT coalesce(jsonb_agg(jsonb_build_object('field','category','value',btrim(path_part),
            'source_path','$.source_category_path['||ordinality||']') ORDER BY ordinality),'[]'::jsonb)
   INTO fact_array
   FROM regexp_split_to_table(coalesce(product_row.source_extra->>'source_category_path',''),'\s*>\s*')
        WITH ORDINALITY AS p(path_part,ordinality)
   WHERE btrim(path_part)<>'';
   p_observation:=jsonb_build_object('contract_version','retailer-facts-2026-v1',
       'source_code',product_row.source_code,'source_product_key',product_row.source_product_key,
       'identity_verified',true,'fetch_state','FETCHED','components','[]'::jsonb,'facts',fact_array);
 END IF;

 -- The normalized audience must agree with the persisted ingress audience. UNKNOWN
 -- is kept unknown. No provider code U or navigation label becomes a new audience.
 IF NOT invalid_evidence AND jsonb_typeof(p_observation->'facts')='array' THEN
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_observation->'facts') f
       WHERE f->>'field'='audience' AND f->>'value' IS DISTINCT FROM product_row.audience_code)
   THEN invalid_evidence:=true;
   ELSE
     p_observation:=jsonb_set(p_observation,'{facts}',p_observation->'facts'||jsonb_build_array(
         jsonb_build_object('field','name','value',product_row.product_name,'source_path','$.product_name'),
         jsonb_build_object('field','audience','value',product_row.audience_code,'source_path','$.audience')));
   END IF;
 END IF;

 IF NOT invalid_evidence THEN
   BEGIN
     
DECLARE result jsonb;
BEGIN
 IF p_observation IS NULL OR jsonb_typeof(p_observation) IS DISTINCT FROM 'object'
    OR p_observation->>'contract_version' IS DISTINCT FROM 'retailer-facts-2026-v1'
    OR coalesce(p_observation->>'source_code','') NOT IN ('uniqlo','musinsa','zara')
    OR length(coalesce(p_observation->>'source_product_key',''))=0
    OR jsonb_typeof(p_observation->'facts') IS DISTINCT FROM 'array'
    OR jsonb_typeof(coalesce(p_observation->'components','[]'::jsonb)) IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INVALID_INPUT'; END IF;
 IF jsonb_array_length(p_observation->'facts')>256
    OR jsonb_array_length(coalesce(p_observation->'components','[]'::jsonb))>32
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INPUT_TOO_LARGE'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_observation->'facts') f
    WHERE jsonb_typeof(f) IS DISTINCT FROM 'object'
       OR jsonb_typeof(f->'field') IS DISTINCT FROM 'string'
       OR jsonb_typeof(f->'value') IS DISTINCT FROM 'string'
       OR jsonb_typeof(f->'source_path') IS DISTINCT FROM 'string'
       OR length(f->>'value')>16000 OR length(f->>'source_path')=0)
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INVALID_FACT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c
    WHERE jsonb_typeof(c) IS DISTINCT FROM 'object'
       OR jsonb_typeof(c->'component_id') IS DISTINCT FROM 'string'
       OR length(coalesce(c->>'component_id',''))=0
       OR jsonb_typeof(c->'measurement_contract_id') IS DISTINCT FROM 'string'
       OR length(coalesce(c->>'measurement_contract_id',''))=0)
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c
        GROUP BY c->>'component_id' HAVING count(*)>1)
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INVALID_COMPONENTS'; END IF;
 IF p_observation->>'fetch_state' IS DISTINCT FROM 'FETCHED'
    OR p_observation->'identity_verified' IS DISTINCT FROM 'true'::jsonb
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_UNVERIFIED_INPUT'; END IF;

 WITH rules AS (
   SELECT * FROM jsonb_to_recordset(policy_value->'rules')
    AS r(rule_id text, dimension text, "values" jsonb, pattern text,
         fields jsonb, unless_pattern text, context text)
 ), facts AS (
   SELECT DISTINCT f->>'field' field,f->>'value' value,f->>'source_path' source_path
   FROM jsonb_array_elements(p_observation->'facts') f
 ), context AS (
   SELECT coalesce(bool_or(field='category' AND value ~* '^(이너웨어|언더웨어|이너웨어 상의|INNER TOPS|INNERWEAR|UNDERWEAR)$'),false) inner_context
   FROM facts
 ), hits AS (
   SELECT r.rule_id,r.dimension,r."values",f.field,f.value,f.source_path
   FROM facts f CROSS JOIN rules r CROSS JOIN context c
   WHERE r.fields ? f.field AND f.value ~* r.pattern
     AND (r.unless_pattern='' OR NOT f.value ~* r.unless_pattern)
     AND (r.context='ANY' OR (r.context='INNER_CONTEXT' AND c.inner_context)
          OR (r.context='OUTER_CONTEXT' AND NOT c.inner_context))
 ), dimensions AS (
   SELECT dimension, jsonb_agg(DISTINCT v ORDER BY v) possible_values
   FROM hits h CROSS JOIN LATERAL jsonb_array_elements(h."values") v
   WHERE NOT EXISTS(SELECT 1 FROM hits h2 WHERE h2.dimension=h.dimension AND NOT h2."values" @> jsonb_build_array(v))
   GROUP BY dimension
 ), garments AS (
   SELECT gt.* FROM fitmatch_vnext.garment_types gt
   JOIN dimensions d ON d.dimension='garment_type_code' AND d.possible_values ? gt.garment_type_code
   WHERE gt.is_active
 ), axes AS (
   SELECT axis_code,value_code FROM fitmatch_vnext.classification_axis_value_authority
   WHERE is_active AND is_verified
 ), audiences AS (
   SELECT DISTINCT value FROM facts WHERE field='audience'
     AND value IN ('MEN','WOMEN','UNISEX','KIDS','BABY')
 ), component_summary AS (
   SELECT count(DISTINCT c->>'component_id') FILTER(WHERE nullif(c->>'component_id','') IS NOT NULL) component_count,
     count(DISTINCT c->>'measurement_contract_id') FILTER(WHERE nullif(c->>'component_id','') IS NOT NULL AND nullif(c->>'measurement_contract_id','') IS NOT NULL) contract_count
   FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c
 ), checks AS (
   SELECT
     EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion') OR
       (SELECT component_count>1 AND contract_count>1 FROM component_summary) excluded,
     EXISTS(SELECT 1 FROM hits WHERE dimension='unsupported_type') unsupported,
     EXISTS(SELECT 1 FROM facts f WHERE field='attribute' AND value LIKE 'sleeve=%'
       AND NOT EXISTS(SELECT 1 FROM hits h WHERE h.source_path=f.source_path AND h.dimension='sleeve_length_code')) unknown_sleeve_attribute,
     EXISTS(SELECT 1 FROM hits WHERE dimension='structure' AND "values" ? 'AMBIGUOUS_BUNDLE') ambiguous_bundle,
     EXISTS(SELECT 1 FROM hits WHERE dimension='garment_type_code' AND field='category') category_corroborated,
     (SELECT count(*)=1 FROM audiences) audience_valid,
     (SELECT count(*) FROM garments) garment_count,
     EXISTS(SELECT 1 FROM hits WHERE dimension='garment_type_code') AND NOT EXISTS(SELECT 1 FROM garments) type_conflict
 ), complete_candidates AS (
   SELECT jsonb_build_object('audience_code',a.value,'category_code',g.category_code,
      'garment_type_code',g.garment_type_code,'comparison_policy_code',g.comparison_policy_code,
      'sleeve_length_code',s.value_code,'lower_length_code',l.value_code,'body_length_code',b.value_code) tuple
   FROM garments g CROSS JOIN audiences a CROSS JOIN checks ch
   CROSS JOIN LATERAL (SELECT value_code FROM axes WHERE axis_code='sleeve_length' AND g.uses_sleeve_length
       UNION ALL SELECT NULL WHERE NOT g.uses_sleeve_length) s
   CROSS JOIN LATERAL (SELECT value_code FROM axes WHERE axis_code='lower_length' AND g.uses_lower_length
       UNION ALL SELECT NULL WHERE NOT g.uses_lower_length) l
   CROSS JOIN LATERAL (SELECT value_code FROM axes WHERE axis_code='body_length' AND g.uses_body_length
       UNION ALL SELECT NULL WHERE NOT g.uses_body_length) b
   WHERE ch.audience_valid AND ch.category_corroborated AND NOT ch.excluded
     AND NOT ch.unsupported AND NOT ch.ambiguous_bundle AND NOT ch.unknown_sleeve_attribute
     AND (g.garment_type_code NOT LIKE 'men\_%' ESCAPE '\' OR a.value='MEN')
     AND (g.garment_type_code NOT LIKE 'women\_%' ESCAPE '\' OR a.value='WOMEN')
     AND (NOT g.uses_sleeve_length OR NOT EXISTS(SELECT 1 FROM hits WHERE dimension='sleeve_length_code')
          OR EXISTS(SELECT 1 FROM dimensions d WHERE d.dimension='sleeve_length_code' AND d.possible_values ? s.value_code))
     AND (NOT g.uses_lower_length OR NOT EXISTS(SELECT 1 FROM hits WHERE dimension='lower_length_code')
          OR EXISTS(SELECT 1 FROM dimensions d WHERE d.dimension='lower_length_code' AND d.possible_values ? l.value_code))
     AND (NOT g.uses_body_length OR NOT EXISTS(SELECT 1 FROM hits WHERE dimension='body_length_code')
          OR EXISTS(SELECT 1 FROM dimensions d WHERE d.dimension='body_length_code' AND d.possible_values ? b.value_code))
 ), candidate_summary AS (
   SELECT coalesce(jsonb_agg(tuple ORDER BY tuple::text),'[]'::jsonb) candidates,count(*) count FROM complete_candidates
 ), fingerprints AS (
   SELECT encode(sha256(convert_to(jsonb_build_object(
     'source_code',p_observation->>'source_code','source_product_key',p_observation->>'source_product_key',
     'contract_version',p_observation->>'contract_version',
     'facts',(SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY field,source_path,value),'[]'::jsonb) FROM facts f),
     'components',(SELECT coalesce(jsonb_agg(c ORDER BY c::text),'[]'::jsonb) FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c)
     )::text,'UTF8')),'hex') input_fingerprint,
     encode(sha256(convert_to(jsonb_build_object('rules',policy_value,
       'garments',(SELECT jsonb_agg(to_jsonb(g) - 'created_at' - 'updated_at' ORDER BY garment_type_code) FROM fitmatch_vnext.garment_types g WHERE is_active),
       'axes',(SELECT jsonb_agg(to_jsonb(a) ORDER BY axis_code,value_code) FROM axes a))::text,'UTF8')),'hex') policy_fingerprint
 ), known AS (
   SELECT dimension,jsonb_agg(v ORDER BY v)->0 value FROM dimensions CROSS JOIN LATERAL jsonb_array_elements(possible_values) v
   WHERE dimension IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
   GROUP BY dimension HAVING count(*)=1
   UNION ALL SELECT 'audience_code',to_jsonb(min(value)) FROM audiences HAVING count(*)=1
 ), common_candidate_fields AS (
   SELECT k,jsonb_agg(DISTINCT v)->0 v FROM complete_candidates c CROSS JOIN LATERAL jsonb_each(c.tuple) e(k,v)
   GROUP BY k HAVING count(DISTINCT v)=1 AND jsonb_agg(DISTINCT v)->0 <> 'null'::jsonb
 ), missing AS (
   SELECT k FROM complete_candidates c CROSS JOIN LATERAL jsonb_each(c.tuple) e(k,v)
   WHERE k IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
   GROUP BY k HAVING count(DISTINCT v)>1
 ), reasons AS (
   SELECT 'NON_APPAREL' code WHERE EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion' AND "values" ? 'NON_APPAREL')
   UNION SELECT 'UPPER_LOWER_SET' WHERE EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion' AND "values" ? 'UPPER_LOWER_SET')
   UNION SELECT 'MULTIPLE_COMPONENT_MEASUREMENT_CONTRACTS' WHERE (SELECT component_count>1 AND contract_count>1 FROM component_summary)
   UNION SELECT 'UNSUPPORTED_GARMENT_TYPE' WHERE (SELECT unsupported FROM checks)
   UNION SELECT 'UNSUPPORTED_RETAILER_AXIS' WHERE (SELECT unknown_sleeve_attribute FROM checks)
   UNION SELECT 'BUNDLE_CONTENTS_UNPROVEN' WHERE (SELECT ambiguous_bundle AND NOT excluded FROM checks)
   UNION SELECT 'TYPE_EVIDENCE_CONFLICT' WHERE (SELECT type_conflict FROM checks)
   UNION SELECT 'MISSING_OR_CONFLICTING_AUDIENCE' WHERE NOT (SELECT audience_valid FROM checks)
   UNION SELECT 'NO_CORROBORATED_TYPE_EVIDENCE' WHERE NOT (SELECT category_corroborated FROM checks)
   UNION SELECT 'TUPLE_OR_AXIS_UNRESOLVED' WHERE (SELECT count=0 FROM candidate_summary) AND NOT (SELECT excluded FROM checks)
   UNION SELECT 'MISSING_REQUIRED_FIELDS' WHERE (SELECT count>1 FROM candidate_summary)
 )
 SELECT jsonb_build_object(
   'verification_state','FETCHED','classification_status',CASE WHEN ch.excluded THEN 'NOT_APPLICABLE' WHEN cs.count=1 THEN 'CONFIRMED' ELSE 'REVIEW_REQUIRED' END,
   'resolver_version','fitmatch-common-evidence-2026-v1','policy_version',policy_value->>'version',
   'product_structure_code',CASE
      WHEN EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion' AND "values" ? 'UPPER_LOWER_SET') THEN 'SET'
      WHEN EXISTS(SELECT 1 FROM hits WHERE dimension='structure' AND "values" ? 'MULTIPACK') THEN 'MULTIPACK'
      ELSE 'UNKNOWN' END,
   'wearing_role',CASE WHEN (SELECT inner_context FROM context) THEN 'INNERWEAR' ELSE NULL END,
   'source_code',p_observation->>'source_code','source_product_key',p_observation->>'source_product_key',
   'input_fingerprint',fp.input_fingerprint,'policy_fingerprint',fp.policy_fingerprint,
   'candidate_set_hash',encode(sha256(convert_to(fp.input_fingerprint||'|'||fp.policy_fingerprint||'|'||cs.candidates::text,'UTF8')),'hex'),
   'reason_codes',(SELECT coalesce(jsonb_agg(code ORDER BY code),'[]'::jsonb) FROM reasons),
   'classification',CASE WHEN NOT ch.excluded AND cs.count=1 THEN cs.candidates->0 ELSE NULL END,
   'fixed_facts',CASE WHEN cs.count>0 THEN (SELECT coalesce(jsonb_object_agg(k,v),'{}'::jsonb) FROM common_candidate_fields) ELSE '{}'::jsonb END,
   'observed_partial_facts',(SELECT coalesce(jsonb_object_agg(dimension,value),'{}'::jsonb) FROM known),
   'unknown_fields',(SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb) FROM missing),
   'candidate_count',cs.count,'candidates',cs.candidates,
   'recovery_action',CASE WHEN ch.excluded THEN 'BLOCK_NOT_APPLICABLE' WHEN cs.count=1 THEN 'USE_RECOMMENDATION' WHEN cs.count>1 THEN 'SELECT_MISSING_FIELDS' ELSE 'ACQUIRE_EVIDENCE_OR_REVIEW_POLICY' END,
   'evidence',(SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY dimension,rule_id,source_path,value),'[]'::jsonb) FROM hits h),
   'comparison_authorized',false,'measurement_readiness','NOT_EVALUATED') INTO result
 FROM checks ch CROSS JOIN candidate_summary cs CROSS JOIN fingerprints fp;
 facts_result := result;
END;

   EXCEPTION WHEN SQLSTATE '22023' THEN
     -- Invalid OPTIONAL classification facts cannot invent authority or abort an
     -- otherwise valid retailer observation. They produce an explicit review block.
     invalid_evidence:=true;
   END;
 END IF;
 IF invalid_evidence THEN
   facts_result:=jsonb_build_object('classification_status','REVIEW_REQUIRED','candidates','[]'::jsonb,
       'candidate_count',0,'reason_codes',jsonb_build_array('INVALID_CURRENT_RETAILER_FACTS'),
       'input_fingerprint',encode(sha256(convert_to(coalesce(envelope,'{}'::jsonb)::text,'UTF8')),'hex'),
       'policy_fingerprint',encode(sha256(convert_to(policy_value::text,'UTF8')),'hex'));
 END IF;

 -- A verified exclusion is never relaxed. Explicit multiple measurement components
 -- are an exclusion even when a historical category mapping was DIRECT.
 IF base->>'classification_status'='NOT_APPLICABLE' THEN RETURN base; END IF;
 IF base->>'comparison_measurement_contract'='MULTIPLE_COMPONENT' THEN
   status_value:='NOT_APPLICABLE'; reason_value:='Multiple component measurement contracts';
 ELSIF facts_result->>'classification_status'='NOT_APPLICABLE' THEN
   status_value:='NOT_APPLICABLE'; reason_value:='Current retailer evidence excludes comparison';
 ELSE
   candidate_values:=coalesce(facts_result->'candidates','[]'::jsonb);
   SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(facts_result->'evidence','[]'::jsonb)) e
       WHERE e->>'field' IN ('name','attribute') AND e->>'dimension' IN
       ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code'))
   INTO product_specific;

   -- Disagreement with a complete verified tuple is a review conflict, never an
   -- automatic replacement. Agreement keeps the existing mapping UUID and version.
   IF base->>'classification_status'='CONFIRMED' THEN
     SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(facts_result->'evidence','[]'::jsonb)) e
       WHERE e->>'dimension' IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
         AND base->>(e->>'dimension') IS NOT NULL
         AND NOT (e->'values' ? (base->>(e->>'dimension')))) INTO conflict;
     conflict:=conflict OR invalid_evidence
        OR coalesce(facts_result->'reason_codes','[]'::jsonb) ?|
           ARRAY['BUNDLE_CONTENTS_UNPROVEN','UNSUPPORTED_GARMENT_TYPE','UNSUPPORTED_RETAILER_AXIS',
                 'TYPE_EVIDENCE_CONFLICT','MISSING_OR_CONFLICTING_AUDIENCE'];
     IF NOT conflict THEN RETURN base; END IF;
     candidate_values:='[]'::jsonb;
     reason_value:='Current retailer facts conflict with verified mapping authority';
   ELSIF base->>'reason' IN ('Equal-top candidates have different outcomes','DIRECT classification tuple is invalid')
     AND NOT (
       base->>'resolution_mode'='CANDIDATE'
       AND NOT EXISTS (
         SELECT 1 FROM fitmatch_vnext.product_classification_signals pcs
         JOIN fitmatch_vnext.source_classification_signals s ON s.id=pcs.source_signal_id AND s.is_active
         JOIN fitmatch_vnext.classification_signal_mappings m ON m.source_signal_id=s.id AND m.is_active AND m.is_verified
         WHERE pcs.product_id=product_row.id AND s.source_code=product_row.source_code
           AND m.audience_code IN ('ANY',product_row.audience_code)
           AND s.signal_kind=(SELECT signal_kind FROM fitmatch_vnext.source_classification_signals
               WHERE id=(base->>'primary_source_signal_id')::uuid)
           AND m.priority=(SELECT priority FROM fitmatch_vnext.classification_signal_mappings WHERE id=(base->>'mapping_id')::uuid)
           AND (m.resolution_mode<>'CANDIDATE' OR s.id<>(base->>'primary_source_signal_id')::uuid)
       )
     ) THEN
     conflict:=true; candidate_values:='[]'::jsonb;
     reason_value:='Existing mapping authority conflict requires remediation';
   END IF;

   -- Explicit CANDIDATE authority is a bound, not a vocabulary hint. Current facts
   -- can narrow it; they cannot introduce a tuple outside the verified candidate set.
   IF NOT conflict AND base->>'resolution_mode'='CANDIDATE' THEN
     SELECT coalesce(jsonb_agg(c ORDER BY c::text),'[]'::jsonb) INTO candidate_values
     FROM jsonb_array_elements(candidate_values) c
     WHERE EXISTS(SELECT 1 FROM fitmatch_vnext.classification_signal_mappings m
       WHERE m.source_signal_id=(base->>'primary_source_signal_id')::uuid
         AND m.is_active AND m.is_verified AND m.resolution_mode='CANDIDATE'
         AND m.priority=(SELECT priority FROM fitmatch_vnext.classification_signal_mappings WHERE id=(base->>'mapping_id')::uuid)
         AND m.audience_code IN ('ANY',product_row.audience_code)
         AND (m.audience_code=product_row.audience_code OR NOT EXISTS (
           SELECT 1 FROM fitmatch_vnext.classification_signal_mappings exact_m
           WHERE exact_m.source_signal_id=m.source_signal_id AND exact_m.is_active AND exact_m.is_verified
             AND exact_m.resolution_mode='CANDIDATE' AND exact_m.priority=m.priority
             AND exact_m.audience_code=product_row.audience_code))
         AND m.garment_type_code=c->>'garment_type_code'
         AND m.sleeve_length_code IS NOT DISTINCT FROM c->>'sleeve_length_code'
         AND m.lower_length_code IS NOT DISTINCT FROM c->>'lower_length_code'
         AND m.body_length_code IS NOT DISTINCT FROM c->>'body_length_code');
   END IF;
   -- Candidate construction uses the active garment's uses_* axes and verified
   -- axis values; SET was excluded above. It already satisfies the pinned deployed
   -- tuple validator, which is additionally exercised by the integration harness
   -- and existing product/override triggers. Do not add a new privileged call to
   -- this existing SECURITY INVOKER reader.

   status_value:=CASE WHEN NOT conflict AND NOT invalid_evidence
       AND facts_result->>'classification_status'='CONFIRMED'
       AND jsonb_array_length(candidate_values)=1
       AND (base->>'resolution_mode' IS DISTINCT FROM 'PRODUCT_REQUIRED' OR product_specific)
       THEN 'CONFIRMED' ELSE 'REVIEW_REQUIRED' END;
   reason_value:=coalesce(reason_value,CASE WHEN status_value='CONFIRMED'
       THEN 'Complete current product-scoped retailer evidence'
       ELSE 'Current retailer facts require explicit completion or additional evidence' END);
 END IF;
 IF status_value='NOT_APPLICABLE' THEN candidate_values:='[]'::jsonb; END IF;
 tuple_value:=CASE WHEN status_value='CONFIRMED' THEN candidate_values->0 ELSE '{}'::jsonb END;
 -- Return a coherent bounded decision, not a stale hash/status from the broader
 -- intermediate vocabulary proposal. Observed partial facts remain diagnostic.
 SELECT coalesce(jsonb_object_agg(k,v),'{}'::jsonb) INTO fixed_value
 FROM (SELECT k,jsonb_agg(DISTINCT v)->0 v FROM jsonb_array_elements(candidate_values) c
       CROSS JOIN LATERAL jsonb_each(c) e(k,v)
       GROUP BY k HAVING count(DISTINCT v)=1 AND jsonb_agg(DISTINCT v)->0<>'null'::jsonb) common;
 SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb) INTO unknown_value
 FROM (SELECT k FROM jsonb_array_elements(candidate_values) c CROSS JOIN LATERAL jsonb_each(c) e(k,v)
       WHERE k IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
       GROUP BY k HAVING count(DISTINCT v)>1) missing;
 facts_result:=facts_result||jsonb_build_object('fact_proposal_status',facts_result->>'classification_status',
     'classification_status',status_value,'classification',CASE WHEN status_value='CONFIRMED' THEN tuple_value ELSE NULL END,
     'candidates',candidate_values,'candidate_count',jsonb_array_length(candidate_values),'authority_conflict',conflict,
     'fixed_facts',fixed_value,'unknown_fields',unknown_value,
     'candidate_set_hash',encode(sha256(convert_to(jsonb_build_object('facts_input',facts_result->>'input_fingerprint',
         'facts_policy',facts_result->>'policy_fingerprint','authority',base,'candidates',candidate_values)::text,'UTF8')),'hex'),
     'recovery_action',CASE WHEN status_value='NOT_APPLICABLE' THEN 'BLOCK_NOT_APPLICABLE'
         WHEN status_value='CONFIRMED' THEN 'USE_RECOMMENDATION'
         WHEN jsonb_array_length(candidate_values)>0 THEN 'SELECT_MISSING_FIELDS' ELSE 'ACQUIRE_EVIDENCE_OR_REVIEW_POLICY' END);
 RETURN jsonb_strip_nulls(jsonb_build_object('found',true,'product_id',product_row.id,
   'source_code',product_row.source_code,'source_product_key',product_row.source_product_key,
   'classification_status',status_value,'resolution_mode',CASE status_value
       WHEN 'CONFIRMED' THEN 'DIRECT' WHEN 'NOT_APPLICABLE' THEN 'NOT_APPLICABLE' ELSE 'REVIEW_REQUIRED' END,
   'garment_type_code',tuple_value->>'garment_type_code','sleeve_length_code',tuple_value->>'sleeve_length_code',
   'lower_length_code',tuple_value->>'lower_length_code','body_length_code',tuple_value->>'body_length_code',
   'audience_code',product_row.audience_code,'product_structure_code',product_row.product_structure_code,
   'comparison_measurement_contract',base->>'comparison_measurement_contract',
   'comparison_unit_eligible',CASE WHEN status_value='NOT_APPLICABLE' THEN 'false'::jsonb ELSE base->'comparison_unit_eligible' END,
   'reason',reason_value,'resolver_version',version_value,
   'input_fingerprint',encode(sha256(convert_to(jsonb_build_object('baseline',base,
       'facts_input',facts_result->>'input_fingerprint','facts_policy',facts_result->>'policy_fingerprint',
       'candidates',candidate_values,'status',status_value,'version',version_value)::text,'UTF8')),'hex')))
   || jsonb_build_object('retailer_fact_decision',facts_result,'mapping_authority_snapshot',base);
END;

 END IF;
 -- The deployed verified-mapping algorithm is retained verbatim as the first authority.
 SELECT old_decision.value INTO base FROM (with recursive product_row as (
    select p.*
    from fitmatch_vnext.products p
    where p.source_code = p_source_code
      and p.source_product_key = p_source_product_key
),

comparison_unit as (
    select
        p.id,
        fitmatch_vnext.product_comparison_unit_decision(p.id) unit
    from product_row p
),

evidence as (
    select
        p.id product_id,
        pcs.source_signal_id,
        pcs.evidence_order,
        ss.signal_kind,
        ss.external_key,

        case ss.signal_kind
            when 'PRODUCT_EXACT' then 600
            when 'PRODUCT_STRUCTURE' then 500
            when 'PRODUCT_TYPE' then 400
            when 'SUBFAMILY' then 300
            when 'FAMILY' then 250
            when 'CATEGORY' then 200
            when 'SECTION' then 150
            else 100
        end evidence_rank

    from product_row p

    join fitmatch_vnext.product_classification_signals pcs
      on pcs.product_id = p.id

    join fitmatch_vnext.source_classification_signals ss
      on ss.id = pcs.source_signal_id
     and ss.source_code = p.source_code
     and ss.is_active
),

raw_candidates as (
    select
        e.*,
        m.id mapping_id,
        m.resolution_mode,
        m.garment_type_code,
        m.sleeve_length_code,
        m.lower_length_code,
        m.body_length_code,
        m.priority,
        m.mapping_version,
        m.mapping_checksum

    from evidence e

    join product_row p
      on p.id = e.product_id

    join fitmatch_vnext.classification_signal_mappings m
      on m.source_signal_id = e.source_signal_id
     and m.is_active
     and m.is_verified
     and (
         m.audience_code = 'ANY'
         or m.audience_code = p.audience_code
     )
     and (
         coalesce(m.mapping_version, '')
            <> 'vnext-uniqlo-complete-path-20260902-v3'
         or fitmatch_vnext.uniqlo_auto_promoted_mapping_is_current(m.id)
     )
),

signal_ancestry(
    descendant_id,
    ancestor_id,
    depth
) as (
    select
        s.id,
        s.parent_signal_id,
        1
    from fitmatch_vnext.source_classification_signals s
    where s.parent_signal_id is not null

    union all

    select
        a.descendant_id,
        s.parent_signal_id,
        a.depth + 1

    from signal_ancestry a

    join fitmatch_vnext.source_classification_signals s
      on s.id = a.ancestor_id

    where s.parent_signal_id is not null
      and a.depth < 16
),

candidates as (
    select
        c.*,
        max(c.evidence_rank) over () max_evidence_rank

    from raw_candidates c

    where not exists (
        select 1
        from raw_candidates d

        join signal_ancestry a
          on a.descendant_id = d.source_signal_id
         and a.ancestor_id = c.source_signal_id

        where d.product_id = c.product_id
          and c.resolution_mode = 'PRODUCT_REQUIRED'
          and d.resolution_mode = 'DIRECT'
          and d.evidence_rank = c.evidence_rank
          and d.priority = c.priority
    )
),

ranked as (
    select
        c.*,
        max(priority) over () max_priority

    from candidates c

    where evidence_rank = max_evidence_rank
),

top_candidates as (
    select *
    from ranked
    where priority = max_priority
),

summary as (
    select
        count(*) candidate_count,

        count(
            distinct concat_ws(
                '|',
                resolution_mode,
                coalesce(garment_type_code, '∅'),
                coalesce(sleeve_length_code, '∅'),
                coalesce(lower_length_code, '∅'),
                coalesce(body_length_code, '∅')
            )
        ) outcome_count

    from top_candidates
),

chosen as (
    select *
    from top_candidates

    order by
        case
            when lower(p_source_code) = 'uniqlo'
             and signal_kind = 'CATEGORY'
            then evidence_order
        end desc nulls last,

        evidence_order,
        source_signal_id,
        mapping_id

    limit 1
),

resolved as (
    select
        p.*,
        unit.unit comparison_unit,

        c.source_signal_id,
        c.mapping_id,
        c.resolution_mode mapping_resolution_mode,

        c.garment_type_code mapped_garment_type_code,
        c.sleeve_length_code mapped_sleeve_length_code,
        c.lower_length_code mapped_lower_length_code,
        c.body_length_code mapped_body_length_code,

        c.mapping_version,
        c.mapping_checksum,

        coalesce(s.candidate_count, 0) candidate_count,
        coalesce(s.outcome_count, 0) outcome_count

    from product_row p

    left join comparison_unit unit
      on unit.id = p.id

    left join summary s
      on true

    left join chosen c
      on true
),

decision as (
    select
        r.*,

        case
            when upper(coalesce(r.product_structure_code, 'UNKNOWN')) = 'SET'
                then 'NOT_APPLICABLE'

            when r.candidate_count = 0
                then 'REVIEW_REQUIRED'

            when r.outcome_count > 1
                then 'REVIEW_REQUIRED'

            when r.mapping_resolution_mode = 'NOT_APPLICABLE'
                then 'NOT_APPLICABLE'

            when r.mapping_resolution_mode = 'DIRECT'
             and coalesce(
                (
                    fitmatch_vnext.classification_tuple_validation(
                        r.mapped_garment_type_code,
                        r.product_structure_code,
                        r.audience_code,
                        r.mapped_sleeve_length_code,
                        r.mapped_lower_length_code,
                        r.mapped_body_length_code
                    ) ->> 'valid'
                )::boolean,
                false
             )
                then 'CONFIRMED'

            else 'REVIEW_REQUIRED'
        end decision_status,

        case
            when upper(coalesce(r.product_structure_code, 'UNKNOWN')) = 'SET'
                then 'Product structure is SET'

            when r.candidate_count = 0
                then 'No active verified mapping candidate'

            when r.outcome_count > 1
                then 'Equal-top candidates have different outcomes'

            when r.mapping_resolution_mode = 'NOT_APPLICABLE'
                then 'Mapping is NOT_APPLICABLE'

            when r.mapping_resolution_mode = 'DIRECT'
             and coalesce(
                (
                    fitmatch_vnext.classification_tuple_validation(
                        r.mapped_garment_type_code,
                        r.product_structure_code,
                        r.audience_code,
                        r.mapped_sleeve_length_code,
                        r.mapped_lower_length_code,
                        r.mapped_body_length_code
                    ) ->> 'valid'
                )::boolean,
                false
             )
                then 'Complete verified DIRECT classification mapping'

            when r.mapping_resolution_mode = 'DIRECT'
                then 'DIRECT classification tuple is invalid'

            when r.mapping_resolution_mode = 'PRODUCT_REQUIRED'
                then 'Product-exact verified evidence is required'

            else 'Mapping requires review'
        end decision_reason

    from resolved r
)

select case

    when not exists (
        select 1 from product_row
    )
    then jsonb_build_object(
        'found', false,
        'classification_status', 'REVIEW_REQUIRED',
        'resolution_mode', 'REVIEW_REQUIRED',
        'reason', 'Unknown source product identity',
        'resolver_version',
            'fitmatch-vnext-resolver-v4-classification-only-uniqlo-deepest-category'
    )

    else (
        select jsonb_strip_nulls(
            jsonb_build_object(
                'found', true,
                'product_id', d.id,
                'source_code', d.source_code,
                'source_product_key', d.source_product_key,

                'classification_status', d.decision_status,

                'resolution_mode',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then 'DIRECT'
                        when d.decision_status = 'NOT_APPLICABLE'
                            then 'NOT_APPLICABLE'
                        else coalesce(
                            d.mapping_resolution_mode,
                            'REVIEW_REQUIRED'
                        )
                    end,

                'garment_type_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_garment_type_code
                    end,

                'product_structure_code',
                    d.product_structure_code,

                'comparison_measurement_contract',
                    d.comparison_unit ->> 'measurement_contract',

                'comparison_unit_eligible',
                    d.comparison_unit -> 'eligible',

                'audience_code',
                    d.audience_code,

                'sleeve_length_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_sleeve_length_code
                    end,

                'lower_length_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_lower_length_code
                    end,

                'body_length_code',
                    case
                        when d.decision_status = 'CONFIRMED'
                            then d.mapped_body_length_code
                    end,

                'primary_source_signal_id',
                    d.source_signal_id,

                'mapping_id',
                    d.mapping_id,

                'mapping_version',
                    d.mapping_version,

                'mapping_checksum',
                    d.mapping_checksum,

                'reason',
                    d.decision_reason,

                'resolver_version',
                    'fitmatch-vnext-resolver-v4-classification-only-uniqlo-deepest-category',

                'input_fingerprint',
                    encode(
                        extensions.digest(
                            concat_ws(
                                '|',
                                d.source_code,
                                d.source_product_key,
                                d.audience_code,
                                d.product_structure_code,
                                coalesce(
                                    d.source_signal_id::text,
                                    '∅'
                                ),
                                coalesce(
                                    d.mapping_checksum,
                                    '∅'
                                ),
                                'fitmatch-vnext-resolver-v4-classification-only-uniqlo-deepest-category'
                            ),
                            'sha256'
                        ),
                        'hex'
                    )
            )
        )

        from decision d
    )

end) old_decision(value);
 IF NOT coalesce((base->>'found')::boolean,false) THEN RETURN base; END IF;
 SELECT * INTO product_row FROM fitmatch_vnext.products WHERE id=(base->>'product_id')::uuid;

 -- Installing this function cannot invalidate existing personal choices or reclassify
 -- stored rows. Existing ingress clears resolver_version only for a NEW observation.
 IF product_row.resolver_version IS NOT NULL AND product_row.resolver_version<>version_value
 THEN RETURN base; END IF;
 IF product_row.source_code NOT IN ('uniqlo','musinsa','zara') THEN RETURN base; END IF;

 -- Existing service-only ingress atomically writes these CURRENT projection fields
 -- and the immutable receipt. Read the public product projection, not the private
 -- receipt table: this existing SECURITY INVOKER reader retains its original grants.
 -- Never use _legacy_source_category_path or carried-forward migration metadata.
 IF coalesce(product_row.source_extra->>'latest_ingestion_fingerprint','') !~ '^[0-9a-f]{64}$'
    OR (product_row.source_extra->>'latest_ingestion_observed_at')::timestamptz
         IS DISTINCT FROM product_row.last_fetched_at
    OR product_row.last_fetched_at IS NULL
 THEN RETURN base; END IF;

 -- Existing service-role ingress already stores these provider facts. The optional
 -- observation supplies additional product attributes, without changing the RPC shape.
 envelope:=product_row.source_extra#>'{structured_facts,classification_observation}';
 IF envelope IS NOT NULL THEN
   IF jsonb_typeof(envelope) IS DISTINCT FROM 'object'
      OR envelope->>'contract_version' IS DISTINCT FROM 'retailer-facts-2026-v1'
      OR envelope->>'source_code' IS DISTINCT FROM product_row.source_code
      OR envelope->>'source_product_key' IS DISTINCT FROM product_row.source_product_key
      OR envelope->>'fetch_state' IS DISTINCT FROM 'FETCHED'
      OR envelope->'identity_verified' IS DISTINCT FROM 'true'::jsonb
   THEN invalid_evidence:=true;
   ELSE p_observation:=envelope;
   END IF;
 ELSE
   SELECT coalesce(jsonb_agg(jsonb_build_object('field','category','value',btrim(path_part),
            'source_path','$.source_category_path['||ordinality||']') ORDER BY ordinality),'[]'::jsonb)
   INTO fact_array
   FROM regexp_split_to_table(coalesce(product_row.source_extra->>'source_category_path',''),'\s*>\s*')
        WITH ORDINALITY AS p(path_part,ordinality)
   WHERE btrim(path_part)<>'';
   p_observation:=jsonb_build_object('contract_version','retailer-facts-2026-v1',
       'source_code',product_row.source_code,'source_product_key',product_row.source_product_key,
       'identity_verified',true,'fetch_state','FETCHED','components','[]'::jsonb,'facts',fact_array);
 END IF;

 -- The normalized audience must agree with the persisted ingress audience. UNKNOWN
 -- is kept unknown. No provider code U or navigation label becomes a new audience.
 IF NOT invalid_evidence AND jsonb_typeof(p_observation->'facts')='array' THEN
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_observation->'facts') f
       WHERE f->>'field'='audience' AND f->>'value' IS DISTINCT FROM product_row.audience_code)
   THEN invalid_evidence:=true;
   ELSE
     p_observation:=jsonb_set(p_observation,'{facts}',p_observation->'facts'||jsonb_build_array(
         jsonb_build_object('field','name','value',product_row.product_name,'source_path','$.product_name'),
         jsonb_build_object('field','audience','value',product_row.audience_code,'source_path','$.audience')));
   END IF;
 END IF;

 IF NOT invalid_evidence THEN
   BEGIN
     
DECLARE result jsonb;
BEGIN
 IF p_observation IS NULL OR jsonb_typeof(p_observation) IS DISTINCT FROM 'object'
    OR p_observation->>'contract_version' IS DISTINCT FROM 'retailer-facts-2026-v1'
    OR coalesce(p_observation->>'source_code','') NOT IN ('uniqlo','musinsa','zara')
    OR length(coalesce(p_observation->>'source_product_key',''))=0
    OR jsonb_typeof(p_observation->'facts') IS DISTINCT FROM 'array'
    OR jsonb_typeof(coalesce(p_observation->'components','[]'::jsonb)) IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INVALID_INPUT'; END IF;
 IF jsonb_array_length(p_observation->'facts')>256
    OR jsonb_array_length(coalesce(p_observation->'components','[]'::jsonb))>32
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INPUT_TOO_LARGE'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_observation->'facts') f
    WHERE jsonb_typeof(f) IS DISTINCT FROM 'object'
       OR jsonb_typeof(f->'field') IS DISTINCT FROM 'string'
       OR jsonb_typeof(f->'value') IS DISTINCT FROM 'string'
       OR jsonb_typeof(f->'source_path') IS DISTINCT FROM 'string'
       OR length(f->>'value')>16000 OR length(f->>'source_path')=0)
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INVALID_FACT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c
    WHERE jsonb_typeof(c) IS DISTINCT FROM 'object'
       OR jsonb_typeof(c->'component_id') IS DISTINCT FROM 'string'
       OR length(coalesce(c->>'component_id',''))=0
       OR jsonb_typeof(c->'measurement_contract_id') IS DISTINCT FROM 'string'
       OR length(coalesce(c->>'measurement_contract_id',''))=0)
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c
        GROUP BY c->>'component_id' HAVING count(*)>1)
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_INVALID_COMPONENTS'; END IF;
 IF p_observation->>'fetch_state' IS DISTINCT FROM 'FETCHED'
    OR p_observation->'identity_verified' IS DISTINCT FROM 'true'::jsonb
 THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='FM_CLASSIFIER_UNVERIFIED_INPUT'; END IF;

 -- Numeric measurements are retained as API evidence. No validated five-way
 -- garment-length calibration exists: they cannot fabricate a length axis.
 IF p_observation ? 'measurement_evidence' THEN
   IF jsonb_typeof(p_observation->'measurement_evidence') IS DISTINCT FROM 'object'
      OR p_observation#>>'{measurement_evidence,source_code}' IS DISTINCT FROM p_observation->>'source_code'
      OR p_observation#>>'{measurement_evidence,source_product_key}' IS DISTINCT FROM p_observation->>'source_product_key'
      OR jsonb_typeof(p_observation#>'{measurement_evidence,records}') IS DISTINCT FROM 'array'
   THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='FM_CLASSIFIER_INVALID_MEASUREMENT_EVIDENCE'; END IF;
   IF jsonb_array_length(p_observation#>'{measurement_evidence,records}')>8192
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_observation#>'{measurement_evidence,records}') m
        WHERE jsonb_typeof(m) IS DISTINCT FROM 'object'
          OR coalesce(m->>'scope','') NOT IN ('GARMENT','BODY','UNKNOWN')
          OR jsonb_typeof(m->'source_path') IS DISTINCT FROM 'string'
          OR coalesce(m->>'source_path','')='')
   THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='FM_CLASSIFIER_INVALID_MEASUREMENT_EVIDENCE'; END IF;
 END IF;

 WITH rules AS (
   SELECT * FROM jsonb_to_recordset(policy_value->'rules')
    AS r(rule_id text, dimension text, "values" jsonb, pattern text,
         fields jsonb, unless_pattern text, context text)
 ), facts AS (
   SELECT DISTINCT f->>'field' field,f->>'value' value,f->>'source_path' source_path
   FROM jsonb_array_elements(p_observation->'facts') f
 ), context AS (
   SELECT coalesce(bool_or(field='category' AND value ~* '^(이너웨어|언더웨어|이너웨어 상의|INNER TOPS|INNERWEAR|UNDERWEAR)$'),false) inner_context
   FROM facts
 ), hits AS (
   SELECT r.rule_id,r.dimension,r."values",f.field,f.value,f.source_path
   FROM facts f CROSS JOIN rules r CROSS JOIN context c
   WHERE r.fields ? f.field AND f.value ~* r.pattern
     AND (r.unless_pattern='' OR NOT f.value ~* r.unless_pattern)
     AND (r.context='ANY' OR (r.context='INNER_CONTEXT' AND c.inner_context)
          OR (r.context='OUTER_CONTEXT' AND NOT c.inner_context))
 ), dimensions AS (
   SELECT dimension, jsonb_agg(DISTINCT v ORDER BY v) possible_values
   FROM hits h CROSS JOIN LATERAL jsonb_array_elements(h."values") v
   WHERE NOT EXISTS(SELECT 1 FROM hits h2 WHERE h2.dimension=h.dimension AND NOT h2."values" @> jsonb_build_array(v))
   GROUP BY dimension
 ), garments AS (
   SELECT gt.* FROM fitmatch_vnext.garment_types gt
   JOIN dimensions d ON d.dimension='garment_type_code' AND d.possible_values ? gt.garment_type_code
   WHERE gt.is_active
 ), axes AS (
   SELECT axis_code,value_code FROM fitmatch_vnext.classification_axis_value_authority
   WHERE is_active AND is_verified
 ), audiences AS (
   SELECT DISTINCT value FROM facts WHERE field='audience'
     AND value IN ('MEN','WOMEN','UNISEX','KIDS','BABY')
 ), component_summary AS (
   SELECT count(DISTINCT c->>'component_id') FILTER(WHERE nullif(c->>'component_id','') IS NOT NULL) component_count,
     count(DISTINCT c->>'measurement_contract_id') FILTER(WHERE nullif(c->>'component_id','') IS NOT NULL AND nullif(c->>'measurement_contract_id','') IS NOT NULL) contract_count
   FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c
 ), checks AS (
   SELECT
     EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion') OR
       (SELECT component_count>1 AND contract_count>1 FROM component_summary) excluded,
     EXISTS(SELECT 1 FROM hits WHERE dimension='unsupported_type') unsupported,
     EXISTS(SELECT 1 FROM facts f WHERE field='attribute' AND (value LIKE 'sleeve=%' OR value LIKE 'pant-length=%')
       AND NOT EXISTS(SELECT 1 FROM hits h WHERE h.source_path=f.source_path AND h.value=f.value
         AND h.dimension=CASE WHEN f.value LIKE 'sleeve=%' THEN 'sleeve_length_code' ELSE 'lower_length_code' END)) unknown_sleeve_attribute,
     EXISTS(SELECT 1 FROM hits WHERE dimension='structure' AND "values" ? 'AMBIGUOUS_BUNDLE') ambiguous_bundle,
     EXISTS(SELECT 1 FROM hits WHERE dimension='garment_type_code' AND field='category') category_corroborated,
     (SELECT count(*)=1 FROM audiences) audience_valid,
     (SELECT count(*) FROM garments) garment_count,
     EXISTS(SELECT 1 FROM hits WHERE dimension='garment_type_code') AND NOT EXISTS(SELECT 1 FROM garments) type_conflict
 ), complete_candidates AS (
   SELECT jsonb_build_object('audience_code',a.value,'category_code',g.category_code,
      'garment_type_code',g.garment_type_code,'comparison_policy_code',g.comparison_policy_code,
      'sleeve_length_code',s.value_code,'lower_length_code',l.value_code,'body_length_code',b.value_code) tuple
   FROM garments g CROSS JOIN audiences a CROSS JOIN checks ch
   CROSS JOIN LATERAL (SELECT value_code FROM axes WHERE axis_code='sleeve_length' AND g.uses_sleeve_length
       UNION ALL SELECT NULL WHERE NOT g.uses_sleeve_length) s
   CROSS JOIN LATERAL (SELECT value_code FROM axes WHERE axis_code='lower_length' AND g.uses_lower_length
       UNION ALL SELECT NULL WHERE NOT g.uses_lower_length) l
   CROSS JOIN LATERAL (SELECT value_code FROM axes WHERE axis_code='body_length' AND g.uses_body_length
       UNION ALL SELECT NULL WHERE NOT g.uses_body_length) b
   WHERE ch.audience_valid AND ch.category_corroborated AND NOT ch.excluded
     AND NOT ch.unsupported AND NOT ch.ambiguous_bundle AND NOT ch.unknown_sleeve_attribute
     AND (g.garment_type_code NOT LIKE 'men\_%' ESCAPE '\' OR a.value='MEN')
     AND (g.garment_type_code NOT LIKE 'women\_%' ESCAPE '\' OR a.value='WOMEN')
     AND (NOT g.uses_sleeve_length OR NOT EXISTS(SELECT 1 FROM hits WHERE dimension='sleeve_length_code')
          OR EXISTS(SELECT 1 FROM dimensions d WHERE d.dimension='sleeve_length_code' AND d.possible_values ? s.value_code))
     AND (NOT g.uses_lower_length OR NOT EXISTS(SELECT 1 FROM hits WHERE dimension='lower_length_code')
          OR EXISTS(SELECT 1 FROM dimensions d WHERE d.dimension='lower_length_code' AND d.possible_values ? l.value_code))
     AND (NOT g.uses_body_length OR NOT EXISTS(SELECT 1 FROM hits WHERE dimension='body_length_code')
          OR EXISTS(SELECT 1 FROM dimensions d WHERE d.dimension='body_length_code' AND d.possible_values ? b.value_code))
 ), candidate_summary AS (
   SELECT coalesce(jsonb_agg(tuple ORDER BY tuple::text),'[]'::jsonb) candidates,count(*) count FROM complete_candidates
 ), fingerprints AS (
   SELECT encode(sha256(convert_to(jsonb_build_object(
     'source_code',p_observation->>'source_code','source_product_key',p_observation->>'source_product_key',
     'contract_version',p_observation->>'contract_version',
     'facts',(SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY field,source_path,value),'[]'::jsonb) FROM facts f),
     'components',(SELECT coalesce(jsonb_agg(c ORDER BY c::text),'[]'::jsonb) FROM jsonb_array_elements(coalesce(p_observation->'components','[]'::jsonb)) c),
     'measurements',(SELECT coalesce(jsonb_agg(m ORDER BY m::text),'[]'::jsonb) FROM jsonb_array_elements(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)) m)
     )::text,'UTF8')),'hex') input_fingerprint,
     encode(sha256(convert_to(jsonb_build_object('rules',policy_value,
       'garments',(SELECT jsonb_agg(to_jsonb(g) - 'created_at' - 'updated_at' ORDER BY garment_type_code) FROM fitmatch_vnext.garment_types g WHERE is_active),
       'axes',(SELECT jsonb_agg(to_jsonb(a) ORDER BY axis_code,value_code) FROM axes a))::text,'UTF8')),'hex') policy_fingerprint
 ), known AS (
   SELECT dimension,jsonb_agg(v ORDER BY v)->0 value FROM dimensions CROSS JOIN LATERAL jsonb_array_elements(possible_values) v
   WHERE dimension IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
   GROUP BY dimension HAVING count(*)=1
   UNION ALL SELECT 'audience_code',to_jsonb(min(value)) FROM audiences HAVING count(*)=1
 ), common_candidate_fields AS (
   SELECT k,jsonb_agg(DISTINCT v)->0 v FROM complete_candidates c CROSS JOIN LATERAL jsonb_each(c.tuple) e(k,v)
   GROUP BY k HAVING count(DISTINCT v)=1 AND jsonb_agg(DISTINCT v)->0 <> 'null'::jsonb
 ), missing AS (
   SELECT k FROM complete_candidates c CROSS JOIN LATERAL jsonb_each(c.tuple) e(k,v)
   WHERE k IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
   GROUP BY k HAVING count(DISTINCT v)>1
 ), reasons AS (
   SELECT 'NON_APPAREL' code WHERE EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion' AND "values" ? 'NON_APPAREL')
   UNION SELECT 'UPPER_LOWER_SET' WHERE EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion' AND "values" ? 'UPPER_LOWER_SET')
   UNION SELECT 'MULTIPLE_COMPONENT_MEASUREMENT_CONTRACTS' WHERE (SELECT component_count>1 AND contract_count>1 FROM component_summary)
   UNION SELECT 'UNSUPPORTED_GARMENT_TYPE' WHERE (SELECT unsupported FROM checks)
   UNION SELECT 'UNSUPPORTED_RETAILER_AXIS' WHERE (SELECT unknown_sleeve_attribute FROM checks)
   UNION SELECT 'BUNDLE_CONTENTS_UNPROVEN' WHERE (SELECT ambiguous_bundle AND NOT excluded FROM checks)
   UNION SELECT 'TYPE_EVIDENCE_CONFLICT' WHERE (SELECT type_conflict FROM checks)
   UNION SELECT 'MISSING_OR_CONFLICTING_AUDIENCE' WHERE NOT (SELECT audience_valid FROM checks)
   UNION SELECT 'NO_CORROBORATED_TYPE_EVIDENCE' WHERE NOT (SELECT category_corroborated FROM checks)
   UNION SELECT 'TUPLE_OR_AXIS_UNRESOLVED' WHERE (SELECT count=0 FROM candidate_summary) AND NOT (SELECT excluded FROM checks)
   UNION SELECT 'MISSING_REQUIRED_FIELDS' WHERE (SELECT count>1 FROM candidate_summary)
 )
 SELECT jsonb_build_object(
   'verification_state','FETCHED','classification_status',CASE WHEN ch.excluded THEN 'NOT_APPLICABLE' WHEN cs.count=1 THEN 'CONFIRMED' ELSE 'REVIEW_REQUIRED' END,
   'resolver_version','fitmatch-common-evidence-2026-v2','policy_version',policy_value->>'version',
   'product_structure_code',CASE
      WHEN EXISTS(SELECT 1 FROM hits WHERE dimension='exclusion' AND "values" ? 'UPPER_LOWER_SET') THEN 'SET'
      WHEN EXISTS(SELECT 1 FROM hits WHERE dimension='structure' AND "values" ? 'MULTIPACK') THEN 'MULTIPACK'
      ELSE 'UNKNOWN' END,
   'wearing_role',CASE WHEN (SELECT inner_context FROM context) THEN 'INNERWEAR' ELSE NULL END,
   'source_code',p_observation->>'source_code','source_product_key',p_observation->>'source_product_key',
   'input_fingerprint',fp.input_fingerprint,'policy_fingerprint',fp.policy_fingerprint,
   'candidate_set_hash',encode(sha256(convert_to(fp.input_fingerprint||'|'||fp.policy_fingerprint||'|'||cs.candidates::text,'UTF8')),'hex'),
   'reason_codes',(SELECT coalesce(jsonb_agg(code ORDER BY code),'[]'::jsonb) FROM reasons),
   'classification',CASE WHEN NOT ch.excluded AND cs.count=1 THEN cs.candidates->0 ELSE NULL END,
   'fixed_facts',CASE WHEN cs.count>0 THEN (SELECT coalesce(jsonb_object_agg(k,v),'{}'::jsonb) FROM common_candidate_fields) ELSE '{}'::jsonb END,
   'observed_partial_facts',(SELECT coalesce(jsonb_object_agg(dimension,value),'{}'::jsonb) FROM known),
   'unknown_fields',(SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb) FROM missing),
   'candidate_count',cs.count,'candidates',cs.candidates,
   'recovery_action',CASE WHEN ch.excluded THEN 'BLOCK_NOT_APPLICABLE' WHEN cs.count=1 THEN 'USE_RECOMMENDATION' WHEN cs.count>1 THEN 'SELECT_MISSING_FIELDS' ELSE 'ACQUIRE_EVIDENCE_OR_REVIEW_POLICY' END,
   'evidence',(SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY dimension,rule_id,source_path,value),'[]'::jsonb) FROM hits h),
   'classification_evidence_basis','API_REPORTED_FACTS',
   'measurement_evidence_summary',jsonb_build_object(
      'record_count',jsonb_array_length(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)),
      'garment_record_count',(SELECT count(*) FROM jsonb_array_elements(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)) m WHERE m->>'scope'='GARMENT'),
      'body_record_count',(SELECT count(*) FROM jsonb_array_elements(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)) m WHERE m->>'scope'='BODY'),
      'missing_unit_count',(SELECT count(*) FROM jsonb_array_elements(coalesce(p_observation#>'{measurement_evidence,records}','[]'::jsonb)) m WHERE nullif(m->>'raw_unit','') IS NULL),
      'numeric_axis_inference','DISABLED_NO_VERIFIED_CALIBRATION',
      'fetch_state',p_observation#>>'{measurement_evidence,fetch_state}'),
   'comparison_authorized',false,'measurement_readiness','NOT_EVALUATED') INTO result
 FROM checks ch CROSS JOIN candidate_summary cs CROSS JOIN fingerprints fp;
 facts_result := result;
END;

   EXCEPTION WHEN SQLSTATE '22023' THEN
     -- Invalid OPTIONAL classification facts cannot invent authority or abort an
     -- otherwise valid retailer observation. They produce an explicit review block.
     invalid_evidence:=true;
   END;
 END IF;
 IF invalid_evidence THEN
   facts_result:=jsonb_build_object('classification_status','REVIEW_REQUIRED','candidates','[]'::jsonb,
       'candidate_count',0,'reason_codes',jsonb_build_array('INVALID_CURRENT_RETAILER_FACTS'),
       'input_fingerprint',encode(sha256(convert_to(coalesce(envelope,'{}'::jsonb)::text,'UTF8')),'hex'),
       'policy_fingerprint',encode(sha256(convert_to(policy_value::text,'UTF8')),'hex'));
 END IF;

 -- A verified exclusion is never relaxed. Explicit multiple measurement components
 -- are an exclusion even when a historical category mapping was DIRECT.
 IF base->>'classification_status'='NOT_APPLICABLE' THEN RETURN base; END IF;
 IF base->>'comparison_measurement_contract'='MULTIPLE_COMPONENT' THEN
   status_value:='NOT_APPLICABLE'; reason_value:='Multiple component measurement contracts';
 ELSIF facts_result->>'classification_status'='NOT_APPLICABLE' THEN
   status_value:='NOT_APPLICABLE'; reason_value:='Current retailer evidence excludes comparison';
 ELSE
   candidate_values:=coalesce(facts_result->'candidates','[]'::jsonb);
   SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(facts_result->'evidence','[]'::jsonb)) e
       WHERE e->>'field' IN ('name','attribute') AND e->>'dimension' IN
       ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code'))
   INTO product_specific;

   -- Disagreement with a complete verified tuple is a review conflict, never an
   -- automatic replacement. Agreement keeps the existing mapping UUID and version.
   IF base->>'classification_status'='CONFIRMED' THEN
     SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(facts_result->'evidence','[]'::jsonb)) e
       WHERE e->>'dimension' IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
         AND base->>(e->>'dimension') IS NOT NULL
         AND NOT (e->'values' ? (base->>(e->>'dimension')))) INTO conflict;
     conflict:=conflict OR invalid_evidence
        OR coalesce(facts_result->'reason_codes','[]'::jsonb) ?|
           ARRAY['BUNDLE_CONTENTS_UNPROVEN','UNSUPPORTED_GARMENT_TYPE','UNSUPPORTED_RETAILER_AXIS',
                 'TYPE_EVIDENCE_CONFLICT','MISSING_OR_CONFLICTING_AUDIENCE'];
     IF NOT conflict THEN RETURN base; END IF;
     candidate_values:='[]'::jsonb;
     reason_value:='Current retailer facts conflict with verified mapping authority';
   ELSIF base->>'reason' IN ('Equal-top candidates have different outcomes','DIRECT classification tuple is invalid')
     AND NOT (
       base->>'resolution_mode'='CANDIDATE'
       AND NOT EXISTS (
         SELECT 1 FROM fitmatch_vnext.product_classification_signals pcs
         JOIN fitmatch_vnext.source_classification_signals s ON s.id=pcs.source_signal_id AND s.is_active
         JOIN fitmatch_vnext.classification_signal_mappings m ON m.source_signal_id=s.id AND m.is_active AND m.is_verified
         WHERE pcs.product_id=product_row.id AND s.source_code=product_row.source_code
           AND m.audience_code IN ('ANY',product_row.audience_code)
           AND s.signal_kind=(SELECT signal_kind FROM fitmatch_vnext.source_classification_signals
               WHERE id=(base->>'primary_source_signal_id')::uuid)
           AND m.priority=(SELECT priority FROM fitmatch_vnext.classification_signal_mappings WHERE id=(base->>'mapping_id')::uuid)
           AND (m.resolution_mode<>'CANDIDATE' OR s.id<>(base->>'primary_source_signal_id')::uuid)
       )
     ) THEN
     conflict:=true; candidate_values:='[]'::jsonb;
     reason_value:='Existing mapping authority conflict requires remediation';
   END IF;

   -- Explicit CANDIDATE authority is a bound, not a vocabulary hint. Current facts
   -- can narrow it; they cannot introduce a tuple outside the verified candidate set.
   IF NOT conflict AND base->>'resolution_mode'='CANDIDATE' THEN
     SELECT coalesce(jsonb_agg(c ORDER BY c::text),'[]'::jsonb) INTO candidate_values
     FROM jsonb_array_elements(candidate_values) c
     WHERE EXISTS(SELECT 1 FROM fitmatch_vnext.classification_signal_mappings m
       WHERE m.source_signal_id=(base->>'primary_source_signal_id')::uuid
         AND m.is_active AND m.is_verified AND m.resolution_mode='CANDIDATE'
         AND m.priority=(SELECT priority FROM fitmatch_vnext.classification_signal_mappings WHERE id=(base->>'mapping_id')::uuid)
         AND m.audience_code IN ('ANY',product_row.audience_code)
         AND (m.audience_code=product_row.audience_code OR NOT EXISTS (
           SELECT 1 FROM fitmatch_vnext.classification_signal_mappings exact_m
           WHERE exact_m.source_signal_id=m.source_signal_id AND exact_m.is_active AND exact_m.is_verified
             AND exact_m.resolution_mode='CANDIDATE' AND exact_m.priority=m.priority
             AND exact_m.audience_code=product_row.audience_code))
         AND m.garment_type_code=c->>'garment_type_code'
         AND m.sleeve_length_code IS NOT DISTINCT FROM c->>'sleeve_length_code'
         AND m.lower_length_code IS NOT DISTINCT FROM c->>'lower_length_code'
         AND m.body_length_code IS NOT DISTINCT FROM c->>'body_length_code');
   END IF;
   -- Candidate construction uses the active garment's uses_* axes and verified
   -- axis values; SET was excluded above. It already satisfies the pinned deployed
   -- tuple validator, which is additionally exercised by the integration harness
   -- and existing product/override triggers. Do not add a new privileged call to
   -- this existing SECURITY INVOKER reader.

   status_value:=CASE WHEN NOT conflict AND NOT invalid_evidence
       AND facts_result->>'classification_status'='CONFIRMED'
       AND jsonb_array_length(candidate_values)=1
       AND (base->>'resolution_mode' IS DISTINCT FROM 'PRODUCT_REQUIRED' OR product_specific)
       THEN 'CONFIRMED' ELSE 'REVIEW_REQUIRED' END;
   reason_value:=coalesce(reason_value,CASE WHEN status_value='CONFIRMED'
       THEN 'Complete current product-scoped retailer evidence'
       ELSE 'Current retailer facts require explicit completion or additional evidence' END);
 END IF;
 IF status_value='NOT_APPLICABLE' THEN candidate_values:='[]'::jsonb; END IF;
 tuple_value:=CASE WHEN status_value='CONFIRMED' THEN candidate_values->0 ELSE '{}'::jsonb END;
 -- Return a coherent bounded decision, not a stale hash/status from the broader
 -- intermediate vocabulary proposal. Observed partial facts remain diagnostic.
 SELECT coalesce(jsonb_object_agg(k,v),'{}'::jsonb) INTO fixed_value
 FROM (SELECT k,jsonb_agg(DISTINCT v)->0 v FROM jsonb_array_elements(candidate_values) c
       CROSS JOIN LATERAL jsonb_each(c) e(k,v)
       GROUP BY k HAVING count(DISTINCT v)=1 AND jsonb_agg(DISTINCT v)->0<>'null'::jsonb) common;
 SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb) INTO unknown_value
 FROM (SELECT k FROM jsonb_array_elements(candidate_values) c CROSS JOIN LATERAL jsonb_each(c) e(k,v)
       WHERE k IN ('garment_type_code','sleeve_length_code','lower_length_code','body_length_code')
       GROUP BY k HAVING count(DISTINCT v)>1) missing;
 facts_result:=facts_result||jsonb_build_object('fact_proposal_status',facts_result->>'classification_status',
     'classification_status',status_value,'classification',CASE WHEN status_value='CONFIRMED' THEN tuple_value ELSE NULL END,
     'candidates',candidate_values,'candidate_count',jsonb_array_length(candidate_values),'authority_conflict',conflict,
     'fixed_facts',fixed_value,'unknown_fields',unknown_value,
     'candidate_set_hash',encode(sha256(convert_to(jsonb_build_object('facts_input',facts_result->>'input_fingerprint',
         'facts_policy',facts_result->>'policy_fingerprint','authority',base,'candidates',candidate_values)::text,'UTF8')),'hex'),
     'recovery_action',CASE WHEN status_value='NOT_APPLICABLE' THEN 'BLOCK_NOT_APPLICABLE'
         WHEN status_value='CONFIRMED' THEN 'USE_RECOMMENDATION'
         WHEN jsonb_array_length(candidate_values)>0 THEN 'SELECT_MISSING_FIELDS' ELSE 'ACQUIRE_EVIDENCE_OR_REVIEW_POLICY' END);
 RETURN jsonb_strip_nulls(jsonb_build_object('found',true,'product_id',product_row.id,
   'source_code',product_row.source_code,'source_product_key',product_row.source_product_key,
   'classification_status',status_value,'resolution_mode',CASE status_value
       WHEN 'CONFIRMED' THEN 'DIRECT' WHEN 'NOT_APPLICABLE' THEN 'NOT_APPLICABLE' ELSE 'REVIEW_REQUIRED' END,
   'garment_type_code',tuple_value->>'garment_type_code','sleeve_length_code',tuple_value->>'sleeve_length_code',
   'lower_length_code',tuple_value->>'lower_length_code','body_length_code',tuple_value->>'body_length_code',
   'audience_code',product_row.audience_code,'product_structure_code',product_row.product_structure_code,
   'comparison_measurement_contract',base->>'comparison_measurement_contract',
   'comparison_unit_eligible',CASE WHEN status_value='NOT_APPLICABLE' THEN 'false'::jsonb ELSE base->'comparison_unit_eligible' END,
   'reason',reason_value,'resolver_version',version_value,
   'input_fingerprint',encode(sha256(convert_to(jsonb_build_object('baseline',base,
       'facts_input',facts_result->>'input_fingerprint','facts_policy',facts_result->>'policy_fingerprint',
       'candidates',candidate_values,'status',status_value,'version',version_value)::text,'UTF8')),'hex')))
   || jsonb_build_object('retailer_fact_decision',facts_result,'mapping_authority_snapshot',base);
END;
$function$;

CREATE OR REPLACE FUNCTION fitmatch_vnext.classification_recovery_options(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    caller_id uuid := auth.uid();
    product_row fitmatch_vnext.products%rowtype;
    base_result jsonb;
    terminal_signal_id uuid;

    raw_candidate_count_value integer := 0;
    candidate_count_value integer := 0;
    category_count_value integer := 0;
    garment_count_value integer := 0;
    sleeve_count_value integer := 0;
    lower_count_value integer := 0;
    body_count_value integer := 0;

    candidates_value jsonb := '[]'::jsonb;
    candidate_set_hash_value text;
    fixed_facts_value jsonb := '{}'::jsonb;
    unknown_fields_value jsonb := '[]'::jsonb;

    contract_version_value constant text :=
        'fitmatch-vnext-recovery-v7-explicit-authority';
begin
    if caller_id is null
       and coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
    then
        raise exception 'Authentication required';
    end if;

    select *
    into product_row
    from fitmatch_vnext.products p
    where p.id = p_product_id;

    if not found then
        raise exception 'Product not found';
    end if;

    -- Only rows explicitly classified under the new ingress contract enter here.
    -- Historical rows and their personal override hashes retain the deployed path.
    if product_row.resolver_version='fitmatch-vnext-retailer-api-20260909-r1' then
      declare
        current_value jsonb; fact_value jsonb; candidate_values jsonb := '[]'::jsonb;
        fixed_value jsonb := '{}'::jsonb; unknown_value jsonb := '[]'::jsonb;
        count_value integer := 0; hash_value text; blocked_reason text;
        contract_value constant text := 'fitmatch-vnext-recovery-retailer-api-20260909-r1';
      begin
        current_value:=fitmatch_vnext.classification_decision(product_row.source_code,product_row.source_product_key);
        fact_value:=current_value->'retailer_fact_decision';
        if product_row.classification_status<>'REVIEW_REQUIRED' then
          blocked_reason:='GLOBAL_CLASSIFICATION_NOT_REVIEW_REQUIRED';
        elsif current_value->>'input_fingerprint' IS DISTINCT FROM product_row.input_fingerprint
           or current_value IS DISTINCT FROM product_row.classification_evidence
           or encode(extensions.digest(current_value::text,'sha256'),'hex') IS DISTINCT FROM product_row.evidence_fingerprint then
          blocked_reason:='STALE_PRODUCT_CLASSIFICATION_REQUIRES_REFRESH';
        elsif coalesce((fact_value->>'authority_conflict')::boolean,false) then
          blocked_reason:='CURRENT_RETAILER_AUTHORITY_CONFLICT';
        else
          candidate_values:=coalesce(fact_value->'candidates','[]'::jsonb);
          count_value:=jsonb_array_length(candidate_values);
          if count_value=0 then blocked_reason:='NO_COMPLETE_CANONICAL_TUPLE_CANDIDATE';
          elsif count_value>64 then blocked_reason:='TOO_MANY_CANONICAL_TUPLE_CANDIDATES';
          end if;
        end if;
        if blocked_reason IS NOT NULL then candidate_values:='[]'::jsonb; count_value:=0; end if;

        select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) into fixed_value
        from (select k,jsonb_agg(distinct v)->0 v
              from jsonb_array_elements(candidate_values) c cross join lateral jsonb_each(c) e(k,v)
              group by k having count(distinct v)=1 and jsonb_agg(distinct v)->0<>'null'::jsonb) fixed;
        fixed_value:=fixed_value||jsonb_build_object('audience_code',product_row.audience_code,
            'product_structure_code',product_row.product_structure_code);
        select coalesce(jsonb_agg(field_name ORDER BY field_order),'[]'::jsonb) into unknown_value
        from (values ('garment_type','garment_type_code',1),('sleeve_length','sleeve_length_code',2),
              ('lower_length','lower_length_code',3),('body_length','body_length_code',4)) fields(field_name,key,field_order)
        where (select count(distinct c->key) from jsonb_array_elements(candidate_values) c)>1;

        select coalesce(jsonb_agg(c||jsonb_build_object('candidate_id',fp,'candidate_fingerprint',fp,
            'display_name',g.display_name) ORDER BY c::text),'[]'::jsonb) into candidate_values
        from jsonb_array_elements(candidate_values) c
        join fitmatch_vnext.garment_types g on g.garment_type_code=c->>'garment_type_code' and g.is_active
        cross join lateral (select encode(extensions.digest(jsonb_build_object(
            'product_id',product_row.id,'input',product_row.input_fingerprint,
            'evidence',product_row.evidence_fingerprint,'resolver',product_row.resolver_version,
            'contract',contract_value,'candidate',c)::text,'sha256'),'hex') fp) fingerprint;
        count_value:=jsonb_array_length(candidate_values);
        if count_value>0 then
          hash_value:=encode(extensions.digest(candidate_values::text,'sha256'),'hex');
        end if;
        return jsonb_build_object('product_id',product_row.id,'global_status',product_row.classification_status,
          'recoverability',case when count_value>0 then 'RECOVERABLE' else 'UNRECOVERABLE' end,
          'unrecoverable_reason',blocked_reason,'fixed_facts',fixed_value,'unknown_fields',unknown_value,
          'candidates',candidate_values,'candidate_count',count_value,'candidate_set_hash',hash_value,
          'product_input_fingerprint',product_row.input_fingerprint,'product_evidence_fingerprint',product_row.evidence_fingerprint,
          'resolver_version',product_row.resolver_version,'candidate_contract_version',contract_value,
          'current_review_reason',current_value->>'reason');
      end;
    end if;

    -- Only rows explicitly classified under the new ingress contract enter here.
    -- Historical rows and their personal override hashes retain the deployed path.
    if product_row.resolver_version='fitmatch-vnext-current-retailer-facts-20260909-v2' then
      declare
        current_value jsonb; fact_value jsonb; candidate_values jsonb := '[]'::jsonb;
        fixed_value jsonb := '{}'::jsonb; unknown_value jsonb := '[]'::jsonb;
        count_value integer := 0; hash_value text; blocked_reason text;
        contract_value constant text := 'fitmatch-vnext-recovery-current-retailer-facts-20260909-v2';
      begin
        current_value:=fitmatch_vnext.classification_decision(product_row.source_code,product_row.source_product_key);
        fact_value:=current_value->'retailer_fact_decision';
        if product_row.classification_status<>'REVIEW_REQUIRED' then
          blocked_reason:='GLOBAL_CLASSIFICATION_NOT_REVIEW_REQUIRED';
        elsif current_value->>'input_fingerprint' IS DISTINCT FROM product_row.input_fingerprint
           or current_value IS DISTINCT FROM product_row.classification_evidence
           or encode(extensions.digest(current_value::text,'sha256'),'hex') IS DISTINCT FROM product_row.evidence_fingerprint then
          blocked_reason:='STALE_PRODUCT_CLASSIFICATION_REQUIRES_REFRESH';
        elsif coalesce((fact_value->>'authority_conflict')::boolean,false) then
          blocked_reason:='CURRENT_RETAILER_AUTHORITY_CONFLICT';
        else
          candidate_values:=coalesce(fact_value->'candidates','[]'::jsonb);
          count_value:=jsonb_array_length(candidate_values);
          if count_value=0 then blocked_reason:='NO_COMPLETE_CANONICAL_TUPLE_CANDIDATE';
          elsif count_value>64 then blocked_reason:='TOO_MANY_CANONICAL_TUPLE_CANDIDATES';
          end if;
        end if;
        if blocked_reason IS NOT NULL then candidate_values:='[]'::jsonb; count_value:=0; end if;

        select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) into fixed_value
        from (select k,jsonb_agg(distinct v)->0 v
              from jsonb_array_elements(candidate_values) c cross join lateral jsonb_each(c) e(k,v)
              group by k having count(distinct v)=1 and jsonb_agg(distinct v)->0<>'null'::jsonb) fixed;
        fixed_value:=fixed_value||jsonb_build_object('audience_code',product_row.audience_code,
            'product_structure_code',product_row.product_structure_code);
        select coalesce(jsonb_agg(field_name ORDER BY field_order),'[]'::jsonb) into unknown_value
        from (values ('garment_type','garment_type_code',1),('sleeve_length','sleeve_length_code',2),
              ('lower_length','lower_length_code',3),('body_length','body_length_code',4)) fields(field_name,key,field_order)
        where (select count(distinct c->key) from jsonb_array_elements(candidate_values) c)>1;

        select coalesce(jsonb_agg(c||jsonb_build_object('candidate_id',fp,'candidate_fingerprint',fp,
            'display_name',g.display_name) ORDER BY c::text),'[]'::jsonb) into candidate_values
        from jsonb_array_elements(candidate_values) c
        join fitmatch_vnext.garment_types g on g.garment_type_code=c->>'garment_type_code' and g.is_active
        cross join lateral (select encode(extensions.digest(jsonb_build_object(
            'product_id',product_row.id,'input',product_row.input_fingerprint,
            'evidence',product_row.evidence_fingerprint,'resolver',product_row.resolver_version,
            'contract',contract_value,'candidate',c)::text,'sha256'),'hex') fp) fingerprint;
        count_value:=jsonb_array_length(candidate_values);
        if count_value>0 then
          hash_value:=encode(extensions.digest(candidate_values::text,'sha256'),'hex');
        end if;
        return jsonb_build_object('product_id',product_row.id,'global_status',product_row.classification_status,
          'recoverability',case when count_value>0 then 'RECOVERABLE' else 'UNRECOVERABLE' end,
          'unrecoverable_reason',blocked_reason,'fixed_facts',fixed_value,'unknown_fields',unknown_value,
          'candidates',candidate_values,'candidate_count',count_value,'candidate_set_hash',hash_value,
          'product_input_fingerprint',product_row.input_fingerprint,'product_evidence_fingerprint',product_row.evidence_fingerprint,
          'resolver_version',product_row.resolver_version,'candidate_contract_version',contract_value,
          'current_review_reason',current_value->>'reason');
      end;
    end if;

    -- Only rows explicitly classified under the new ingress contract enter here.
    -- Historical rows and their personal override hashes retain the deployed path.
    if product_row.resolver_version='fitmatch-vnext-current-retailer-facts-20260909-v1' then
      declare
        current_value jsonb; fact_value jsonb; candidate_values jsonb := '[]'::jsonb;
        fixed_value jsonb := '{}'::jsonb; unknown_value jsonb := '[]'::jsonb;
        count_value integer := 0; hash_value text; blocked_reason text;
        contract_value constant text := 'fitmatch-vnext-recovery-current-retailer-facts-20260909-v1';
      begin
        current_value:=fitmatch_vnext.classification_decision(product_row.source_code,product_row.source_product_key);
        fact_value:=current_value->'retailer_fact_decision';
        if product_row.classification_status<>'REVIEW_REQUIRED' then
          blocked_reason:='GLOBAL_CLASSIFICATION_NOT_REVIEW_REQUIRED';
        elsif current_value->>'input_fingerprint' IS DISTINCT FROM product_row.input_fingerprint
           or current_value IS DISTINCT FROM product_row.classification_evidence
           or encode(extensions.digest(current_value::text,'sha256'),'hex') IS DISTINCT FROM product_row.evidence_fingerprint then
          blocked_reason:='STALE_PRODUCT_CLASSIFICATION_REQUIRES_REFRESH';
        elsif coalesce((fact_value->>'authority_conflict')::boolean,false) then
          blocked_reason:='CURRENT_RETAILER_AUTHORITY_CONFLICT';
        else
          candidate_values:=coalesce(fact_value->'candidates','[]'::jsonb);
          count_value:=jsonb_array_length(candidate_values);
          if count_value=0 then blocked_reason:='NO_COMPLETE_CANONICAL_TUPLE_CANDIDATE';
          elsif count_value>64 then blocked_reason:='TOO_MANY_CANONICAL_TUPLE_CANDIDATES';
          end if;
        end if;
        if blocked_reason IS NOT NULL then candidate_values:='[]'::jsonb; count_value:=0; end if;

        select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) into fixed_value
        from (select k,jsonb_agg(distinct v)->0 v
              from jsonb_array_elements(candidate_values) c cross join lateral jsonb_each(c) e(k,v)
              group by k having count(distinct v)=1 and jsonb_agg(distinct v)->0<>'null'::jsonb) fixed;
        fixed_value:=fixed_value||jsonb_build_object('audience_code',product_row.audience_code,
            'product_structure_code',product_row.product_structure_code);
        select coalesce(jsonb_agg(field_name ORDER BY field_order),'[]'::jsonb) into unknown_value
        from (values ('garment_type','garment_type_code',1),('sleeve_length','sleeve_length_code',2),
              ('lower_length','lower_length_code',3),('body_length','body_length_code',4)) fields(field_name,key,field_order)
        where (select count(distinct c->key) from jsonb_array_elements(candidate_values) c)>1;

        select coalesce(jsonb_agg(c||jsonb_build_object('candidate_id',fp,'candidate_fingerprint',fp,
            'display_name',g.display_name) ORDER BY c::text),'[]'::jsonb) into candidate_values
        from jsonb_array_elements(candidate_values) c
        join fitmatch_vnext.garment_types g on g.garment_type_code=c->>'garment_type_code' and g.is_active
        cross join lateral (select encode(extensions.digest(jsonb_build_object(
            'product_id',product_row.id,'input',product_row.input_fingerprint,
            'evidence',product_row.evidence_fingerprint,'resolver',product_row.resolver_version,
            'contract',contract_value,'candidate',c)::text,'sha256'),'hex') fp) fingerprint;
        count_value:=jsonb_array_length(candidate_values);
        if count_value>0 then
          hash_value:=encode(extensions.digest(candidate_values::text,'sha256'),'hex');
        end if;
        return jsonb_build_object('product_id',product_row.id,'global_status',product_row.classification_status,
          'recoverability',case when count_value>0 then 'RECOVERABLE' else 'UNRECOVERABLE' end,
          'unrecoverable_reason',blocked_reason,'fixed_facts',fixed_value,'unknown_fields',unknown_value,
          'candidates',candidate_values,'candidate_count',count_value,'candidate_set_hash',hash_value,
          'product_input_fingerprint',product_row.input_fingerprint,'product_evidence_fingerprint',product_row.evidence_fingerprint,
          'resolver_version',product_row.resolver_version,'candidate_contract_version',contract_value,
          'current_review_reason',current_value->>'reason');
      end;
    end if;

    -- 기존 v6 wrapper 전체를 먼저 실행한다.
    base_result :=
        fitmatch_vnext.classification_recovery_options_v7_pre_explicit_core(
            p_product_id
        );

    -- 기존 안전한 v6 결과는 candidate hash 포함 완전히 보존.
    if base_result ->> 'recoverability' = 'RECOVERABLE' then
        return base_result;
    end if;

    if product_row.classification_status <> 'REVIEW_REQUIRED' then
        return base_result;
    end if;

    -- EXACT contract invalid / generic ambiguity / too many candidates 등
    -- 기존 특수 fail-closed guard는 절대 우회하지 않는다.
    if coalesce(base_result ->> 'unrecoverable_reason', '') not in (
        'NO_COMPLETE_CANONICAL_TUPLE_CANDIDATE',
        'REVIEW_REASON_NOT_PRODUCT_REQUIRED'
    ) then
        return base_result;
    end if;

    -- 현재 상품의 가장 깊은 ACTIVE retailer CATEGORY만 사용.
    -- parent/child descendant 후보 승격은 하지 않는다.
    select s.id
    into terminal_signal_id
    from fitmatch_vnext.product_classification_signals pcs
    join fitmatch_vnext.source_classification_signals s
      on s.id = pcs.source_signal_id
     and s.source_code = product_row.source_code
     and s.signal_kind = 'CATEGORY'
     and s.is_active
    where pcs.product_id = product_row.id
    order by pcs.evidence_order desc, s.id
    limit 1;

    if terminal_signal_id is null then
        return base_result;
    end if;

    with
    candidate_rows as (
        select
            m.id mapping_id,
            m.mapping_checksum,
            m.mapping_version,
            m.audience_code,
            m.garment_type_code,
            m.sleeve_length_code,
            m.lower_length_code,
            m.body_length_code,
            m.priority,
            gt.category_code,
            gt.comparison_policy_code,
            gt.display_name,
            gt.sort_order
        from fitmatch_vnext.classification_signal_mappings m
        join fitmatch_vnext.garment_types gt
          on gt.garment_type_code = m.garment_type_code
         and gt.is_active
        where m.source_signal_id = terminal_signal_id
          and m.resolution_mode = 'CANDIDATE'
          and m.is_active
          and m.is_verified
          and (
              m.audience_code = product_row.audience_code
              or (
                  m.audience_code = 'ANY'
                  and not exists (
                      select 1
                      from fitmatch_vnext.classification_signal_mappings exact_m
                      where exact_m.source_signal_id = terminal_signal_id
                        and exact_m.resolution_mode = 'CANDIDATE'
                        and exact_m.is_active
                        and exact_m.is_verified
                        and exact_m.audience_code = product_row.audience_code
                  )
              )
          )
    ),

    valid_candidates as (
        select c.*
        from candidate_rows c
        where coalesce(
            (
                fitmatch_vnext.classification_tuple_validation(
                    c.garment_type_code,
                    product_row.product_structure_code,
                    product_row.audience_code,
                    c.sleeve_length_code,
                    c.lower_length_code,
                    c.body_length_code
                ) ->> 'valid'
            )::boolean,
            false
        )
    ),

    fingerprinted as (
        select
            c.*,
            encode(
                extensions.digest(
                    concat_ws(
                        '|',
                        product_row.id::text,
                        product_row.input_fingerprint,
                        product_row.evidence_fingerprint,
                        product_row.resolver_version,
                        terminal_signal_id::text,
                        c.mapping_id::text,
                        c.mapping_checksum,
                        c.mapping_version,
                        c.category_code,
                        c.garment_type_code,
                        coalesce(c.sleeve_length_code, '∅'),
                        coalesce(c.lower_length_code, '∅'),
                        coalesce(c.body_length_code, '∅'),
                        c.comparison_policy_code,
                        contract_version_value
                    ),
                    'sha256'
                ),
                'hex'
            ) candidate_fingerprint
        from valid_candidates c
    ),

    aggregate_value as (
        select
            (select count(*)::integer from candidate_rows)
                raw_candidate_count,

            count(*)::integer candidate_count,

            count(distinct category_code)::integer category_count,
            count(distinct garment_type_code)::integer garment_count,

            count(
                distinct coalesce(sleeve_length_code, '∅')
            )::integer sleeve_count,

            count(
                distinct coalesce(lower_length_code, '∅')
            )::integer lower_count,

            count(
                distinct coalesce(body_length_code, '∅')
            )::integer body_count,

            coalesce(
                jsonb_agg(
                    jsonb_build_object(
                        'candidate_id', candidate_fingerprint,
                        'candidate_fingerprint', candidate_fingerprint,
                        'display_name', display_name,
                        'category_code', category_code,
                        'garment_type_code', garment_type_code,
                        'sleeve_length_code', sleeve_length_code,
                        'lower_length_code', lower_length_code,
                        'body_length_code', body_length_code,
                        'comparison_policy_code', comparison_policy_code
                    )
                    order by
                        sort_order,
                        garment_type_code,
                        coalesce(sleeve_length_code, '∅'),
                        coalesce(lower_length_code, '∅'),
                        coalesce(body_length_code, '∅'),
                        mapping_id
                ),
                '[]'::jsonb
            ) candidates,

            encode(
                extensions.digest(
                    coalesce(
                        string_agg(
                            candidate_fingerprint,
                            E'\n'
                            order by candidate_fingerprint
                        ),
                        ''
                    ),
                    'sha256'
                ),
                'hex'
            ) candidate_set_hash

        from fingerprinted
    )

    select
        av.raw_candidate_count,
        av.candidate_count,
        av.category_count,
        av.garment_count,
        av.sleeve_count,
        av.lower_count,
        av.body_count,
        av.candidates,
        av.candidate_set_hash
    into
        raw_candidate_count_value,
        candidate_count_value,
        category_count_value,
        garment_count_value,
        sleeve_count_value,
        lower_count_value,
        body_count_value,
        candidates_value,
        candidate_set_hash_value
    from aggregate_value av;

    -- 후보가 없거나, 실제 상품 tuple validation에서 일부만 탈락하거나,
    -- 후보 수가 bounded contract를 벗어나거나, category가 교차하면 fail-closed.
    if raw_candidate_count_value = 0
       or raw_candidate_count_value <> candidate_count_value
       or candidate_count_value not between 1 and 3
       or category_count_value <> 1
    then
        return base_result;
    end if;

    fixed_facts_value := jsonb_strip_nulls(
        jsonb_build_object(
            'audience_code',
                product_row.audience_code,

            'product_structure_code',
                product_row.product_structure_code,

            'category_code',
                case
                    when category_count_value = 1
                    then candidates_value -> 0 ->> 'category_code'
                end,

            'garment_type_code',
                case
                    when garment_count_value = 1
                    then candidates_value -> 0 ->> 'garment_type_code'
                end,

            'sleeve_length_code',
                case
                    when sleeve_count_value = 1
                    then candidates_value -> 0 ->> 'sleeve_length_code'
                end,

            'lower_length_code',
                case
                    when lower_count_value = 1
                    then candidates_value -> 0 ->> 'lower_length_code'
                end,

            'body_length_code',
                case
                    when body_count_value = 1
                    then candidates_value -> 0 ->> 'body_length_code'
                end,

            'comparison_policy_code',
                case
                    when garment_count_value = 1
                    then candidates_value -> 0 ->> 'comparison_policy_code'
                end
        )
    );

    select coalesce(
        jsonb_agg(field_name order by field_order),
        '[]'::jsonb
    )
    into unknown_fields_value
    from (
        values
            ('garment_type', 1, garment_count_value > 1),
            ('sleeve_length', 2, sleeve_count_value > 1),
            ('lower_length', 3, lower_count_value > 1),
            ('body_length', 4, body_count_value > 1)
    ) fields(field_name, field_order, is_unknown)
    where is_unknown;

    return jsonb_build_object(
        'product_id',
            product_row.id,

        'global_status',
            product_row.classification_status,

        'recoverability',
            'RECOVERABLE',

        'unrecoverable_reason',
            null,

        'fixed_facts',
            fixed_facts_value,

        'unknown_fields',
            unknown_fields_value,

        'candidates',
            candidates_value,

        'candidate_count',
            candidate_count_value,

        'product_input_fingerprint',
            product_row.input_fingerprint,

        'product_evidence_fingerprint',
            product_row.evidence_fingerprint,

        'resolver_version',
            product_row.resolver_version,

        'candidate_contract_version',
            contract_version_value,

        'candidate_set_hash',
            candidate_set_hash_value,

        'current_review_reason',
            fitmatch_vnext.classification_decision(
                product_row.source_code,
                product_row.source_product_key
            ) ->> 'reason',

        'explicit_authority_recovery',
            true,

        'terminal_source_signal_id',
            terminal_signal_id
    );
end
$function$;

DO $post$ BEGIN
 IF NOT coalesce((EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('fitmatch_vnext.classification_decision(text,text)') AND md5(replace(prosrc,chr(13),''))='56e82046a4f6d0a279f16eb1f34da992')),false) THEN RAISE EXCEPTION 'FM_PROVIDER_POSTCHECK: procedure_1_installed'; END IF;
 IF NOT coalesce((EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('fitmatch_vnext.classification_decision(text,text)') AND proacl::text='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres,anon=X/postgres}' AND prosecdef=false AND proconfig=ARRAY['search_path=""']::text[])),false) THEN RAISE EXCEPTION 'FM_PROVIDER_POSTCHECK: procedure_1_privileges'; END IF;
 IF NOT coalesce((EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)') AND md5(replace(prosrc,chr(13),''))='d8a1a17c94d33b1a9d5170ab4270e7f1')),false) THEN RAISE EXCEPTION 'FM_PROVIDER_POSTCHECK: procedure_2_installed'; END IF;
 IF NOT coalesce((EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)') AND proacl::text='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' AND prosecdef=true AND proconfig=ARRAY['search_path=""']::text[])),false) THEN RAISE EXCEPTION 'FM_PROVIDER_POSTCHECK: procedure_2_privileges'; END IF;
 IF NOT coalesce((has_function_privilege('service_role',to_regprocedure('public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'),'EXECUTE') AND NOT has_function_privilege('anon',to_regprocedure('public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'),'EXECUTE') AND NOT has_function_privilege('authenticated',to_regprocedure('public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'),'EXECUTE')),false) THEN RAISE EXCEPTION 'FM_PROVIDER_POSTCHECK: ingress_service_only'; END IF;
END $post$;
COMMIT;
-- SELECT only. Installation checks are not semantic release approval.
SELECT 'procedure_1_installed' check_name, coalesce((EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('fitmatch_vnext.classification_decision(text,text)') AND md5(replace(prosrc,chr(13),''))='56e82046a4f6d0a279f16eb1f34da992')),false) passed
UNION ALL
SELECT 'procedure_1_privileges' check_name, coalesce((EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('fitmatch_vnext.classification_decision(text,text)') AND proacl::text='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres,anon=X/postgres}' AND prosecdef=false AND proconfig=ARRAY['search_path=""']::text[])),false) passed
UNION ALL
SELECT 'procedure_2_installed' check_name, coalesce((EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)') AND md5(replace(prosrc,chr(13),''))='d8a1a17c94d33b1a9d5170ab4270e7f1')),false) passed
UNION ALL
SELECT 'procedure_2_privileges' check_name, coalesce((EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('fitmatch_vnext.classification_recovery_options(uuid)') AND proacl::text='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' AND prosecdef=true AND proconfig=ARRAY['search_path=""']::text[])),false) passed
UNION ALL
SELECT 'ingress_service_only' check_name, coalesce((has_function_privilege('service_role',to_regprocedure('public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'),'EXECUTE') AND NOT has_function_privilege('anon',to_regprocedure('public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'),'EXECUTE') AND NOT has_function_privilege('authenticated',to_regprocedure('public.fitmatch_vnext_ingest_product_observation(jsonb,uuid)'),'EXECUTE')),false) passed
ORDER BY check_name;
