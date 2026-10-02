"""Render the read-only DB dictionary snapshot. Does not contact or modify DB.
Usage: python3 scripts/build-data-support-register.py
Not a replacement for deployed resolver tests or live product observations.
"""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]/'Docs/DataSupport'
d=json.loads((root/'db-snapshot-20260917.json').read_text())
def safe(v):
 if v is None:return '—'
 if isinstance(v,bool):return 'Y' if v else 'N'
 if isinstance(v,list):return ' > '.join(map(str,v))
 return str(v).replace('|','\\|').replace('\n',' ')
def table(headers,rows):
 return '| '+' | '.join(headers)+' |\n|'+ '|'.join(['---']*len(headers))+'|\n'+''.join('| '+' | '.join(map(safe,row))+' |\n' for row in rows)
sources={x['source_measurement_code']:x for x in d['source_measurements']}
canon={x['measurement_code']:x for x in d['canonical']}
mappings={x['source_measurement_code']:x for x in d['mappings']}
policies={x['policy_code']:x for x in d['policies']}
rows=[]
for a in sorted(d['aliases'],key=lambda x:(x['source_code'],x['parser_code'] or '',x['raw_code'] or '',x['fitmatch_category_code'] or '')):
 s=sources.get(a['source_measurement_code'],{});m=mappings.get(a['source_measurement_code'],{});c=canon.get(m.get('fitmatch_measurement_code'),{})
 ready=all([a['is_active'],a['is_verified'],s.get('is_active'),s.get('is_comparable'),m.get('is_active'),m.get('is_verified'),c.get('is_active')])
 policy=[x['comparison_policy_code'] for x in d['metrics'] if x['is_active'] and policies.get(x['comparison_policy_code'],{}).get('is_active') and x['fitmatch_measurement_code']==m.get('fitmatch_measurement_code') and m.get('fitmatch_measurement_code')]
 rows.append([a['source_code'],a['parser_code'],a['raw_code'],a['raw_label'],a['fitmatch_category_code'],a['garment_type_code'],a['priority'],a['is_active'],a['is_verified'],a['source_measurement_code'],s.get('native_unit_code'),s.get('measurement_basis_code'),s.get('representation_code'),m.get('fitmatch_measurement_code'),m.get('scale_factor'),m.get('offset_value'),'静的接続あり' if ready else '接続条件要確認',len(set(policy))])
# Korean labels, not runtime support verdicts.
for row in rows:row[-2]={'静的接続あり':'정적 연결 있음','接続条件要確認':'연결 조건 확인 필요'}[row[-2]]
(root/'실측연결목록.md').write_text('# 실측 연결 목록\n\n2026-09-17 DB snapshot. 227 alias 행 기준. 정적 연결은 resolver 실행 PASS가 아님. 공란 문맥은 일반 규칙일 수 있으며 우선순위/충돌/단위를 실제 함수로 확인해야 함. 정책 수는 활성 정책·metric에 등록된 수이며 해당 상품에서 사용됐다는 뜻이 아님. source-native metric 경로는 이 canonical 집계에 포함하지 않으며 원본 JSON metrics 참조.\n\n'+table(['쇼핑몰','parser','raw code','raw label','category','garment','priority','alias활성','alias검증','source code','단위','측정기준','표현','canonical','배율','offset','정적상태','정책등록수'],rows))
(root/'카테고리목록.md').write_text('# 카테고리 사전 목록\n\n현재 조회함수에서 사용하는 retailer-comparison-groups-v3-seven-20260911 정책의 530행. 사전 등록이지 모든 URL의 runtime 분류 성공 보장이 아님. product override/원문 경로/ID 증거도 판정에 관여. UNMAPPED는 사용자 선택 경로.\n\n'+table(['쇼핑몰','정확한 키','원문 경로','그룹','처리','정책'],[[x[k] for k in ['source_code','source_category_key','category_path','group_code','disposition','policy_version']] for x in sorted(d['categories'],key=lambda x:(x['source_code'],x['source_category_key']))]))
rows=[]
for code,s in sorted(sources.items()):
 aliases=[a for a in d['aliases'] if a['source_measurement_code']==code and a['is_active'] and a['is_verified']]
 m=mappings.get(code,{})
 rows.append([s['source_code'],code,s['display_name'],s['is_active'],s['is_comparable'],len(aliases),m.get('fitmatch_measurement_code'),m.get('is_active'),m.get('is_verified')])
(root/'원본실측등록목록.md').write_text('# source 등록 현황\n\n51개 source 정의를 기준으로 alias가 없는 항목도 포함. 원문 보존 전용일 수 있으므로 비활성/미연결을 자동 결함으로 보지 않음.\n\n'+table(['쇼핑몰','source code','표시명','활성','비교용','활성검증alias수','canonical','mapping활성','mapping검증'],rows))
print({k:len(v) for k,v in d.items()})
