#!/usr/bin/env python3
"""Collect balanced, non-overlapping Musinsa apparel from official category/detail responses."""
import argparse, concurrent.futures, hashlib, json, re, threading, time, urllib.request
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) FitMatchResearch/1.0"
GROUPS={"상의":"001","아우터":"002","하의":"003"}
DEFAULT_QUOTAS={"상의":110,"하의":105,"아우터":105}

def core(v): return str(v).split('-')[0]
def old_ids(paths):
    out=set()
    for p in paths:
        for x in json.loads(p.read_text(encoding='utf-8'))['products']:
            if x['source']=='musinsa':
                product_id=x.get('product_key') or x.get('product_id')
                if product_id is not None: out.add(core(product_id))
    return out

class Limiter:
    def __init__(self,delay): self.delay=delay; self.lock=threading.Lock(); self.next=0.0
    def wait(self):
        with self.lock:
            now=time.monotonic(); wait=max(0,self.next-now); self.next=max(now,self.next)+self.delay
        if wait: time.sleep(wait)

def get(url,referer,limiter):
    limiter.wait(); req=urllib.request.Request(url,headers={'User-Agent':UA,'Referer':referer})
    with urllib.request.urlopen(req,timeout=30) as r: return r.read(),r.status,r.geturl()

def category_codes(seed_dir):
    codes=set()
    for p in (seed_dir/'raw/musinsa/category-pages').glob('*.html'):
        text=p.read_text(encoding='utf-8',errors='replace')
        codes.update(re.findall(r'"categoryCode":"((?:001|002|003)\d{3})"',text))
    return sorted(codes)

def discover(code,limiter):
    url=f'https://www.musinsa.com/category/{code}/goods?gf=A'
    body,_,_=get(url,'https://www.musinsa.com',limiter)
    text=body.decode('utf-8',errors='replace')
    ids=set(re.findall(r'"goodsNo":(\d+)',text))
    ids.update(re.findall(r'/products/(\d+)',text))
    return code,url,sorted(ids),body

def detail(item,out,limiter):
    group,code,referer,pid=item; url=f'https://goods-detail.musinsa.com/api2/goods/{pid}'
    try:
        file=out/'raw/musinsa/products'/f'{pid}.json'
        if file.exists():
            body=file.read_bytes(); status=200; final=url
        else:
            body,status,final=get(url,referer,limiter)
        payload=json.loads(body); data=payload.get('data') or {}
        path=data.get('baseCategoryFullPath') or ''
        if not path: return None
        if not file.exists(): file.write_bytes(body)
        return {'group':group,'code':code,'source':'musinsa','product_key':pid,
          'product_name':data.get('goodsNm') or '', 'brand':data.get('brand') or '',
          'exposure_paths':[path], 'size_declared':data.get('isUseSize'),
          'raw_evidence':[{'path':str(file.relative_to(ROOT)),'url':final,'status':status,
            'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest()}]}
    except Exception as e: return {'error':str(e),'product_key':pid,'group':group}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--seed-dir',type=Path,required=True)
    ap.add_argument('--old-manifest',type=Path,action='append',required=True); ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--top-quota',type=int,default=DEFAULT_QUOTAS['상의'])
    ap.add_argument('--bottom-quota',type=int,default=DEFAULT_QUOTAS['하의'])
    ap.add_argument('--outerwear-quota',type=int,default=DEFAULT_QUOTAS['아우터'])
    ap.add_argument('--delay-ms',type=int,default=250); ap.add_argument('--workers',type=int,default=8); a=ap.parse_args()
    quotas={'상의':a.top_quota,'하의':a.bottom_quota,'아우터':a.outerwear_quota}
    target=sum(quotas.values())
    if target <= 0 or any(value < 0 for value in quotas.values()):
        raise SystemExit('quotas must be non-negative and total must be positive')
    out=a.output if a.output.is_absolute() else ROOT/a.output; out.mkdir(parents=True,exist_ok=True)
    (out/'raw/musinsa/category-pages').mkdir(parents=True,exist_ok=True); (out/'raw/musinsa/products').mkdir(parents=True,exist_ok=True)
    limiter=Limiter(a.delay_ms/1000); old=old_ids([p if p.is_absolute() else ROOT/p for p in a.old_manifest])
    codes=category_codes(a.seed_dir if a.seed_dir.is_absolute() else ROOT/a.seed_dir)
    pages=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as ex:
        for code,url,ids,body in ex.map(lambda c:discover(c,limiter),codes):
            (out/'raw/musinsa/category-pages'/f'{code}.html').write_bytes(body); pages.append((code,url,ids))
    candidates=[]; seen=set(old)
    for code,url,ids in pages:
        group=next(k for k,prefix in GROUPS.items() if code.startswith(prefix))
        for pid in ids:
            if pid not in seen: seen.add(pid); candidates.append((group,code,url,pid))
    results=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as ex:
        for i,r in enumerate(ex.map(lambda x:detail(x,out,limiter),candidates),1):
            if r: results.append(r)
            if i%50==0: print(json.dumps({'hydrated':i,'valid':sum('error' not in x for x in results)}),flush=True)
    selected=[]
    for group in ('상의','하의','아우터'):
        pool=[r for r in results if 'error' not in r and r['group']==group]
        pool.sort(key=lambda x:(not bool(x['size_declared']),x['code'],x['product_key']))
        selected.extend(pool[:quotas[group]])
    if len(selected)!=target: raise SystemExit(f'only {len(selected)} selected: {Counter(x["group"] for x in selected)}')
    products=[{k:v for k,v in r.items() if k not in ('group','code','size_declared')} | {
      'observed_ids':[r['product_key']], 'selection':'balanced_official_category_non_overlapping',
      'size_declared':r['size_declared']} for r in selected]
    manifest={'definition':'Balanced Musinsa apparel, excluded against all supplied baselines.',
      'product_count':target,'quotas':quotas,'baseline_manifests':[str(p) for p in a.old_manifest],
      'products':products,'failures':[r for r in results if 'error' in r]}
    (out/'clothing_product_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'selected':target,'groups':Counter(r['group'] for r in selected),
      'size_declared':sum(r['size_declared'] is True for r in selected),'old_ids':len(old)},ensure_ascii=False,default=dict))

if __name__=='__main__': main()
