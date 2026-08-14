#!/usr/bin/env python3
"""Download actual-size and option evidence for a stored Musinsa corpus."""
import argparse, concurrent.futures, hashlib, json, threading, time, urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]; UA='Mozilla/5.0 FitMatchResearch/1.0'
class Limiter:
 def __init__(self,d): self.d=d; self.lock=threading.Lock(); self.next=0.0
 def wait(self):
  with self.lock: now=time.monotonic(); w=max(0,self.next-now); self.next=max(now,self.next)+self.d
  if w: time.sleep(w)
def fetch(pid,out,lim):
 result={'product_id':pid}
 for kind,suffix in [('actual_size','actual-size'),('options','options')]:
  url=f'https://goods-detail.musinsa.com/api2/goods/{pid}/{suffix}'
  try:
   lim.wait(); req=urllib.request.Request(url,headers={'User-Agent':UA,'Accept':'application/json','Referer':'https://www.musinsa.com'})
   with urllib.request.urlopen(req,timeout=30) as r: body=r.read(); status=r.status
   path=out/kind/f'{pid}.json'; path.write_bytes(body); payload=json.loads(body); data=payload.get('data') or {}
   sizes=data.get('sizes') or [] if kind=='actual_size' else []
   result[kind]={'status':status,'path':str(path.relative_to(ROOT)),'bytes':len(body),
    'sha256':hashlib.sha256(body).hexdigest(),'row_count':len(sizes),
    'type_name':data.get('typeName') if kind=='actual_size' else None}
  except Exception as e: result[kind]={'status':0,'error':str(e),'row_count':0}
 return result
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--corpus',type=Path,required=True);ap.add_argument('--workers',type=int,default=8);ap.add_argument('--delay-ms',type=int,default=250);a=ap.parse_args()
 corpus=a.corpus if a.corpus.is_absolute() else ROOT/a.corpus; manifest=json.loads((corpus/'clothing_product_manifest.json').read_text(encoding='utf-8'))
 out=corpus/'raw/musinsa';(out/'actual_size').mkdir(parents=True,exist_ok=True);(out/'options').mkdir(parents=True,exist_ok=True);lim=Limiter(a.delay_ms/1000)
 with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as ex: rows=list(ex.map(lambda p:fetch(str(p['product_key']),out,lim),manifest['products']))
 summary={'products':len(rows),'actual_size_http_success':sum(r['actual_size']['status']==200 for r in rows),
  'actual_size_with_rows':sum(r['actual_size']['row_count']>0 for r in rows),'actual_size_rows':sum(r['actual_size']['row_count'] for r in rows),
  'options_http_success':sum(r['options']['status']==200 for r in rows),'products_detail':rows}
 (corpus/'musinsa_size_evidence.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in summary.items() if k!='products_detail'}))
if __name__=='__main__':main()
