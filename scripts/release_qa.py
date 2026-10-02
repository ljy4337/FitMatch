#!/usr/bin/env python3
"""Release preparation orchestration. Never implements FitMatch product logic."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
from urllib.parse import urlsplit
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / 'Docs/QA/ReleasePreparation20261002'
DATA = DOC / 'data'
DEV = 'https://hnkplvyegonlhumlejst.supabase.co'


def safe_database_url(value):
    try:
        u = urlsplit(value)
        return (u.scheme == 'https' and u.hostname == 'hnkplvyegonlhumlejst.supabase.co'
                and not u.username and not u.password and u.port in (None, 443)
                and u.path in ('', '/') and not u.query and not u.fragment)
    except ValueError:
        return False


def overall_exit(records):
    return 0 if records and all(r['status'] == 'PASS' for r in records) else 2


def validate_case_receipt(receipt, expected_ids):
    """A test method passing is not evidence that every requested case executed."""
    if not expected_ids or len(set(expected_ids)) != len(expected_ids):
        return 'FAIL'
    cases = receipt.get('cases') if isinstance(receipt, dict) else None
    if not isinstance(cases, list): return 'BLOCKED'
    if any(not isinstance(c, dict) or not isinstance(c.get('id'), str)
           or c.get('status') not in ('PASS', 'FAIL', 'BLOCKED', 'NOT RUN') for c in cases):
        return 'FAIL'
    ids = [c['id'] for c in cases]
    if len(set(ids)) != len(ids) or set(ids) - set(expected_ids): return 'FAIL'
    if any(c['status'] == 'FAIL' for c in cases): return 'FAIL'
    if set(ids) != set(expected_ids) or any(c['status'] != 'PASS' for c in cases):
        return 'BLOCKED'
    return 'PASS'


def authenticated_receipt_status(receipt, run_id, expected_ids):
    if not isinstance(receipt, dict): return 'BLOCKED'
    status=validate_case_receipt(receipt,expected_ids)
    if status=='FAIL' or receipt.get('status')=='FAIL': return 'FAIL'
    if (status!='PASS' or receipt.get('status')!='PASS'
            or receipt.get('project')!='hnkplvyegonlhumlejst'
            or str(receipt.get('run_id','')).lower()!=run_id.lower()
            or receipt.get('swift_owner_proof') is not True
            or not str(receipt.get('cleanup','')).startswith('PASS:')):
        return 'BLOCKED'
    return 'PASS'


def cleanup_receipt_status(receipt, run_id):
    status=authenticated_receipt_status(receipt,run_id,['AUTH-VERIFY','LEDGER-CLEANUP'])
    if status=='PASS' and receipt.get('evidence_kind')!='authenticated_swift_ledger_cleanup':
        return 'BLOCKED'
    return status


def safe_overrides(env):
    keys = ('FITMATCH_SUPABASE_URL', 'FITMATCH_QA_DB_URL',
            'TEST_RUNNER_FITMATCH_SUPABASE_URL', 'SIMCTL_CHILD_FITMATCH_SUPABASE_URL',
            'TEST_RUNNER_FITMATCH_QA_DB_URL', 'SIMCTL_CHILD_FITMATCH_QA_DB_URL')
    return all(safe_database_url(env[k]) for k in keys if k in env)


def xcode_selector(selector):
    return selector+'()' if selector.count('/') == 2 and not selector.endswith(')') else selector


def discovery_valid(data, selectors):
    if data.get('errors'): return False
    identifiers = []
    def visit(value):
        if isinstance(value, dict):
            if 'identifier' in value: identifiers.append(value['identifier'].replace('()', ''))
            for v in value.values(): visit(v)
        elif isinstance(value, list):
            for v in value: visit(v)
    visit(data.get('values', []))
    return bool(selectors) and all(any(i == s.replace('()', '') or i.startswith(s.replace('()', '')+'/') for i in identifiers) for s in selectors)


def xcode_status(code, summary):
    if summary.get('failedTests', 0): return 'FAIL'
    if code or not summary.get('passedTests', 0) or summary.get('skippedTests', 0): return 'BLOCKED'
    return 'PASS'


def redact(text):
    text = re.sub(r'(?i)(Bearer\s+)\S+', r'\1[REDACTED]', text)
    text = re.sub(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[REDACTED_JWT]', text)
    text = re.sub(r'\b[A-Za-z0-9_.+%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', '[REDACTED_EMAIL]', text)
    for key, value in os.environ.items():
        if re.search('TOKEN|SECRET|PASSWORD|PUBLISHABLE_KEY|SERVICE_ROLE|ANON_KEY|PUBLIC_KEY', key) and len(value) > 5:
            text = text.replace(value, '[REDACTED]')
    return text


def verify_lock(path):
    if not path.exists(): return ['Missing SHA256SUMS']
    errors = []
    seen = set()
    for row in path.read_text().splitlines():
        if not row.strip() or row.startswith('#'): continue
        expected, name = row.split(maxsplit=1)
        if name in seen: errors.append('Duplicate lock path: '+name)
        seen.add(name)
        relative = name.lstrip('* ')
        target = ((ROOT if relative.startswith('Docs/') else path.parent) / relative).resolve()
        if not target.is_relative_to(ROOT) and not target.is_relative_to(path.parent.resolve()):
            errors.append('Unsafe lock path: '+name); continue
        if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
            errors.append('Changed/missing: '+name)
    if not seen: errors.append('Empty checksum list')
    return errors


def write_report(out, report):
    out.mkdir(parents=True, exist_ok=True)
    required = {'environment.qa_target', 'safety.db_target', 'data.freeze', 'data.urls',
                'policy.expectations', 'environment.simulator', 'environment.disk',
                'tool.xcodebuild', 'tool.swift', 'tool.python3', 'db.contract'}
    mode = report.get('mode')
    if mode == 'cleanup': required = {'db.swift_cleanup'}
    if mode not in ('preflight', 'smoke', 'full', 'cleanup'):
        if not any(r['id'] == 'report.invalid_mode' for r in report['results']):
            report['results'].append({'id':'report.invalid_mode','status':'FAIL',
                                      'detail':'Missing or unknown execution mode; evidence cannot be assessed'})
    if mode in ('smoke','full'):
        required |= {'tool.selftest','tool.db_selftest','app.build_execution','app.discovery',
                     'matrix.synthetic_coverage', 'db.swift_manual',
                     'parser.live_execution','parser.live.input_coverage','parser.live.musinsa','parser.live.uniqlo','parser.live.zara'}
        try:
            for file in (['smoke-selectors.json'] if mode=='smoke' else ['smoke-selectors.json','full-selectors.json']):
                required |= {c['id'] for c in json.loads((DOC/file).read_text())['cases']}
        except Exception: required.add('manifest.required_cases')
    if mode=='full': required |= {'integration.swift_db_A_to_H','integration.cross_provider_3x3','sequence.complete_chains'}
    if mode:
        present = {r['id'] for r in report['results']}
        for identity in sorted(required-present):
            report['results'].append({'id':identity,'status':'NOT RUN','detail':'Required evidence missing'})
        if len(present) != len([r for r in report['results'] if r['id'] in present]):
            report['results'].append({'id':'report.duplicate_ids','status':'FAIL','detail':'Duplicate result IDs'})
    states = [r['status'] for r in report['results']]
    report['overall'] = ('PASS' if overall_exit(report['results']) == 0 else
                         'FAIL' if 'FAIL' in states else 'BLOCKED')
    report['finished_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
    (out/'results.json').write_text(redact(json.dumps(report, ensure_ascii=False, indent=2))+'\n')
    rows = ['# FitMatch Release QA', '', 'Run: '+report['run_id'],
            'Overall: **'+report['overall']+'**', '',
            'Preparation smoke is not release approval. Mock, live parser and DB evidence are separate.', '',
            '| ID | Status | Evidence |', '|---|---|---|']
    rows += ['| {} | {} | {} |'.format(r['id'], r['status'], str(r.get('detail','')).replace('|','/').replace('\n',' ')) for r in report['results']]
    (out/'report.md').write_text(redact('\n'.join(rows))+'\n')
    return overall_exit(report['results'])


def capture(cmd, timeout=30, env=None):
    try:
        r = subprocess.run(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
        return r.returncode, r.stdout, redact(r.stderr)
    except (OSError, subprocess.TimeoutExpired) as e:
        return 124, '', redact(str(e))


def logged(cmd, path, timeout=1800, env=None):
    """Sanitize before any log write. Bounded process group, no retry loop."""
    import threading
    with path.open('w') as log:
        log.write(redact('COMMAND: '+ ' '.join(map(str, cmd)))+'\n')
        try:
            p = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, start_new_session=True)
        except OSError as e:
            log.write(redact(str(e))); return 127
        def stream():
            for line in p.stdout:
                log.write(redact(line)); log.flush()
        worker = threading.Thread(target=stream, daemon=True); worker.start()
        try: code = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGTERM)
            try: p.wait(timeout=10)
            except subprocess.TimeoutExpired: os.killpg(p.pid, signal.SIGKILL); p.wait()
            code = 124
        worker.join(timeout=10)
        return code


def item(report, identity, status, detail):
    report['results'].append({'id':identity, 'status':status, 'detail':detail})
    print(identity+': '+status, flush=True)


def preflight(report, out):
    code, head, _ = capture(['git','rev-parse','HEAD'])
    _, branch, _ = capture(['git','branch','--show-current'])
    _, dirty, _ = capture(['git','status','--porcelain=v1','--untracked-files=all'])
    report.update(head=head.strip(), branch=branch.strip(), worktree=dirty.splitlines())
    item(report, 'environment.qa_target', 'PASS' if branch.strip() == 'QA' else 'BLOCKED', 'QA branch required; actual='+branch.strip())
    for tool, args in [('xcodebuild',['-version']), ('swift',['--version']), ('python3',['--version'])]:
        c, s, e = capture([tool]+args)
        item(report, 'tool.'+tool, 'PASS' if c == 0 else 'BLOCKED', s.strip() or e)
    # Inspect the source of runtime configuration; never dump public/private keys.
    try:
        c, raw, e = capture(['plutil','-convert','json','-o','-','FitMatch.xcodeproj/project.pbxproj'])
        objects = json.loads(raw)['objects']
        configs = [o for o in objects.values() if o.get('isa') == 'XCBuildConfiguration' and o.get('name') in ('Debug-QA','Release-QA')]
        urls = [(o['name'],o['buildSettings']['FITMATCH_SUPABASE_URL']) for o in configs if 'FITMATCH_SUPABASE_URL' in o.get('buildSettings',{})]
        scheme = ET.parse(ROOT/'FitMatch.xcodeproj/xcshareddata/xcschemes/FitMatch-QA.xcscheme').getroot()
        good = (set(name for name, _ in urls) == {'Debug-QA','Release-QA'}
                and all(safe_database_url(url) for _,url in urls)
                and scheme.find('TestAction').get('buildConfiguration') == 'Debug-QA'
                and scheme.find('LaunchAction').get('buildConfiguration') == 'Debug-QA')
        for variable in scheme.findall('.//EnvironmentVariable'):
            if variable.get('isEnabled') == 'YES' and variable.get('key') == 'FITMATCH_SUPABASE_URL':
                good = good and safe_database_url(variable.get('value',''))
        good = good and safe_overrides(os.environ)
        item(report, 'safety.db_target', 'PASS' if good else 'BLOCKED', 'QA Run/Test + both QA build configurations + shell overrides checked')
    except Exception as e:
        item(report, 'safety.db_target', 'BLOCKED', str(e))
    errors = verify_lock(DATA/'SHA256SUMS') + verify_lock(DOC/'plan-SHA256SUMS')
    try:
        locked = {line.split(maxsplit=1)[1].strip() for line in (DATA/'SHA256SUMS').read_text().splitlines() if line.strip()}
        required_data = {str((DATA/n).relative_to(ROOT)) for n in ('url-manifest.json','fixture-index.json','smoke-urls.txt')}
        fixtures = json.loads((DATA/'fixture-index.json').read_text())['items']
        required_data |= {f['path'] for f in fixtures}
        if required_data-locked: errors.append('Required corpus entries absent from lock')
        for f in fixtures:
            if hashlib.sha256((ROOT/f['path']).read_bytes()).hexdigest()!=f['sha256']:
                errors.append('Fixture index hash mismatch: '+f['id'])
    except Exception as e: errors.append(str(e))
    item(report, 'data.freeze', 'FAIL' if errors else 'PASS', '; '.join(errors) or 'SHA-256 fixed corpus matches')
    try:
        manifest = json.loads((DATA/'url-manifest.json').read_text())
        counts = {provider:sum(x['provider']==provider for x in manifest['items']) for provider in ['musinsa','uniqlo','zara']}
        item(report, 'data.urls', 'PASS' if all(n>=30 for n in counts.values()) else 'BLOCKED', str(counts)+'; inventory only, not live validation')
    except Exception as e: item(report, 'data.urls', 'BLOCKED', str(e))
    policy = DOC/'policy-expectations.json'
    try:
        unresolved = [x['id'] for x in json.loads(policy.read_text())['expectations'] if x['status']=='UNRESOLVED']
        item(report, 'policy.expectations', 'BLOCKED' if unresolved else 'PASS', 'UNRESOLVED: '+','.join(unresolved) if unresolved else 'Documented independent policy basis')
    except Exception as e: item(report,'policy.expectations','BLOCKED',str(e))
    item(report,'environment.disk','PASS' if shutil.disk_usage('/tmp').free>=700*1024*1024 else 'BLOCKED',
         'Free bytes='+str(shutil.disk_usage('/tmp').free)+'; 700MiB minimum to attempt reused build, not a guarantee')
    c,s,e = capture(['xcrun','simctl','list','devices','available','-j'])
    try:
        devices = [d for group in json.loads(s)['devices'].values() for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
        selected = os.environ.get('FITMATCH_QA_SIMULATOR_ID')
        selected = next((d for d in devices if d['udid']==selected), None) if selected else next((d for d in devices if d['state']=='Booted'), devices[0] if devices else None)
        report['simulator'] = selected
        item(report,'environment.simulator','PASS' if selected else 'BLOCKED',selected['name'] if selected else 'No available iPhone')
    except Exception: item(report,'environment.simulator','BLOCKED',e or 'simctl unavailable')


def test_results(bundle, out, label):
    c,s,e = capture(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)],120)
    if c: return {}, {}
    summary=json.loads(s); (out/(label+'-summary.json')).write_text(redact(s))
    c,t,e=capture(['xcrun','xcresulttool','get','test-results','tests','--path',str(bundle)],120)
    tree=json.loads(t) if c==0 else {}
    (out/(label+'-tests.json')).write_text(redact(json.dumps(tree,ensure_ascii=False,indent=2)))
    return summary,tree


def matched_test_status(tree, selector):
    suffix=selector.removeprefix('FitMatchTests/').replace('()','')
    found=[]
    def walk(node):
        identifier=node.get('nodeIdentifier','').replace('()','')
        if node.get('nodeType')=='Test Case' and (identifier==suffix or identifier.startswith(suffix+'/')):
            found.append(node.get('result',''))
        for x in node.get('children',[]): walk(x)
    for n in tree.get('testNodes',[]): walk(n)
    if not found: return 'NOT RUN'
    if any(x=='Failed' for x in found): return 'FAIL'
    return 'PASS' if all(x=='Passed' for x in found) else 'BLOCKED'


def record_matrix_receipt(report, out, mode):
    try:
        binding_data = (DOC/'matrix-binding-v2.json').read_bytes()
        binding = json.loads(binding_data)
        expected = (binding['smoke_case_ids'] if mode == 'smoke'
                    else [row['id'] for row in binding['case_bindings']])
        receipt = json.loads((out/('matrix-'+mode+'.json')).read_text())
        if not isinstance(receipt, dict): raise ValueError('Receipt must be an object')
        status = validate_case_receipt(receipt, expected)
        if (receipt.get('mode') != mode
                or receipt.get('binding_sha256') != hashlib.sha256(binding_data).hexdigest()
                or receipt.get('corpus_sha256') != binding['corpus_sha256']
                or receipt.get('evidence_scope') != 'synthetic_production_owner_probe'):
            status = 'FAIL'
        item(report, 'matrix.synthetic_coverage', status,
             'Exact requested case IDs; synthetic Swift-owner probes only, not server group/retailer proof')
        for case in receipt.get('cases', []):
            if isinstance(case, dict) and case.get('id') in expected:
                item(report, 'matrix.synthetic.'+case['id'], case.get('status', 'BLOCKED'),
                     case.get('failure') or case.get('limitation', 'Synthetic production-owner probe'))
        report['matrix_receipt'] = {'path':'matrix-'+mode+'.json', 'expected_count':len(expected),
                                    'actual_count':len(receipt.get('cases', [])),
                                    'evidence_scope':'synthetic_production_owner_probe'}
    except (OSError, ValueError, KeyError, TypeError) as e:
        item(report, 'matrix.synthetic_coverage', 'BLOCKED', 'Missing or invalid matrix execution receipt: '+str(e))


def run_xcode(report,out,mode):
    cases_path=DOC/('smoke-selectors.json' if mode=='smoke' else 'full-selectors.json')
    try:
        cases=json.loads(cases_path.read_text())['cases']
        if mode=='full': cases += json.loads((DOC/'smoke-selectors.json').read_text())['cases']
    except Exception as e: item(report,'app.tests','BLOCKED',str(e)); return
    selectors=list(dict.fromkeys(x['selector'] for x in cases if x.get('selector')))
    can=all(next((r['status']=='PASS' for r in report['results'] if r['id']==name),False) for name in ['environment.simulator','safety.db_target','data.freeze','environment.disk'])
    if not can:
        for c in cases: item(report,c['id'],'BLOCKED','Local execution prerequisites not satisfied')
        item(report,'parser.live','BLOCKED','Local execution prerequisites not satisfied'); return
    destination='platform=iOS Simulator,id='+report['simulator']['udid']
    derived=os.environ.get('FITMATCH_QA_DERIVED_DATA','/tmp/FitMatchEnvironmentBuild')
    base=['xcodebuild','-quiet','-project','FitMatch.xcodeproj','-scheme','FitMatch-QA','-configuration','Debug-QA',
          '-destination',destination,'-derivedDataPath',derived,'-disableAutomaticPackageResolution',
          '-parallel-testing-enabled','NO','ONLY_ACTIVE_ARCH=YES']
    # An explicit test target excludes UI suites, massive live suites and DB scripts.
    opts=['-only-testing:'+xcode_selector(s) for s in selectors]
    bundle=out/'app.xcresult'
    test_env=os.environ.copy()
    test_env['TEST_RUNNER_FITMATCH_QA_MATRIX_OUTPUT']=str(out)
    code=logged(base+opts+['-resultBundlePath',str(bundle),'test'],out/'app.log',1800,test_env)
    summary,tree=test_results(bundle,out,'app')
    report['app_test_summary']=summary
    item(report,'app.build_execution',xcode_status(code,summary),'exit='+str(code)+'; '+str({k:summary.get(k) for k in ['passedTests','failedTests','skippedTests']}))
    for c in cases:
        item(report,c['id'],matched_test_status(tree,c['selector']) if c.get('selector') else 'BLOCKED',c.get('evidence','')+'; '+c.get('selector','No executable selector'))
    record_matrix_receipt(report,out,mode)
    # Fresh discovery records: execution tree above proves what actually ran.
    enum=out/'discovered-tests.json'
    ec=logged(base+opts+['-enumerate-tests','-test-enumeration-style','flat','-test-enumeration-format','json','-test-enumeration-output-path',str(enum),'test-without-building'],out/'discovery.log',180)
    try: discovered = ec==0 and discovery_valid(json.loads(enum.read_text()),selectors)
    except Exception: discovered = False
    item(report,'app.discovery','PASS' if discovered else 'BLOCKED','exit='+str(ec)+'; parsed errors and requested selector coverage')
    if not summary.get('passedTests',0):
        item(report,'parser.live','BLOCKED','Test build unavailable'); return
    urls=DATA/'smoke-urls.txt'
    if mode=='full':
        urls=out/'full-urls.txt'
        urls.write_text('\n'.join(x['url'] for x in json.loads((DATA/'url-manifest.json').read_text())['items'])+'\n')
    env=os.environ.copy()
    for k,v in {'FITMATCH_RELEASE_URLS':str(urls),'FITMATCH_RELEASE_OUTPUT':str(out/'live-parser.json')}.items():
        env['TEST_RUNNER_'+k]=v
    live_bundle=out/'live-parser.xcresult'
    live_opts=['-only-testing:FitMatchTests/FitMatchReleaseLiveProductAuditTests','-test-timeouts-enabled','YES',
               '-default-test-execution-time-allowance','240' if mode=='smoke' else '7200',
               '-maximum-test-execution-time-allowance','300' if mode=='smoke' else '7200']
    code=logged(base+live_opts+['-resultBundlePath',str(live_bundle),'test-without-building'],out/'live-parser.log',420 if mode=='smoke' else 7500,env)
    summ,_=test_results(live_bundle,out,'live-parser')
    item(report,'parser.live_execution',xcode_status(code,summ),'exit='+str(code)+'; actual ProductURLParserService; no DB writes')
    try:
        rows=json.loads((out/'live-parser.json').read_text())
        expected=urls.read_text().splitlines()
        complete=len(rows)==len(expected) and sorted(r['url'] for r in rows)==sorted(expected)
        item(report,'parser.live.input_coverage','PASS' if complete else 'BLOCKED','Exact requested URL multiset must match returned rows')
        for provider,host in [('musinsa','musinsa'),('uniqlo','uniqlo'),('zara','zara')]:
            subset=[x for x in rows if host in urlsplit(x['url']).hostname]
            item(report,'parser.live.'+provider,'BLOCKED' if not complete else 'PASS' if subset and all(x['status']=='PARSED_WITH_MEASUREMENTS' for x in subset) else 'FAIL',str([{'status':x['status'],'sizes':len(x.get('sizes',[]))} for x in subset]))
    except Exception as e: item(report,'parser.live.records','BLOCKED',str(e))


def run_db(report,out,mode):
    if not next((r['status']=='PASS' for r in report['results'] if r['id']=='safety.db_target'),False):
        item(report,'db.contract','BLOCKED','Unsafe target; no write started')
        if mode!='preflight': item(report,'db.swift_manual','BLOCKED','Unsafe target; no write started')
        return
    dbscript=ROOT/'scripts/release_qa_db.py'
    if not dbscript.exists(): item(report,'db.contract','BLOCKED','DB harness missing'); return
    cmd=[sys.executable,str(dbscript),'preflight','--output',str(out/'db-preflight.json')]
    pc=logged(cmd,out/'db-preflight.log',60)
    if pc!=0 or mode=='preflight':
        item(report,'db.contract','FAIL' if pc==1 else 'BLOCKED' if pc else 'PASS','Dedicated authenticated DB preflight exit='+str(pc)+'; db-preflight.json')
        if mode!='preflight': item(report,'db.swift_manual','BLOCKED','Dedicated authenticated preflight has not passed; no Swift DB request')
        return
    report['db_run_id']=str(uuid.uuid5(uuid.NAMESPACE_URL, report['run_id']))
    cmd=[sys.executable,str(dbscript),'smoke','--run-id',report['db_run_id'],'--output',str(out/'db-smoke.json')]
    code=logged(cmd,out/'db.log',180)
    if (out/'db-smoke.json').exists(): report['db_evidence']=json.loads((out/'db-smoke.json').read_text())
    item(report,'db.contract','PASS' if code==0 else 'BLOCKED' if code==2 else 'FAIL','Direct authenticated RPC contract proof; exit='+str(code)+'; db-smoke.json')
    if code:
        item(report,'db.swift_manual','BLOCKED','Prior authenticated RPC smoke or cleanup incomplete; inspect DB ledger')
        return
    run_authenticated_swift(report,out,mode)


def run_authenticated_swift(report,out,mode):
    required=['FITMATCH_QA_DB_'+key for key in ('URL','PUBLIC_KEY','DEDICATED_USERS',
              'USER_A_TOKEN','USER_A_ID','USER_B_TOKEN','USER_B_ID',
              'USER_A_REFRESH_TOKEN','USER_B_REFRESH_TOKEN')]
    missing=[key for key in required if not os.environ.get(key)]
    if missing or not report.get('app_test_summary',{}).get('passedTests'):
        item(report,'db.swift_manual','BLOCKED','Missing dedicated session/build: '+','.join(missing))
        return
    if not safe_database_url(os.environ['FITMATCH_QA_DB_URL']) or not safe_overrides(os.environ):
        item(report,'db.swift_manual','BLOCKED','Unsafe target; no request started')
        return
    tasks=[('db.swift_manual','manual','dedicatedDevelopmentAccountsExerciseRealSwiftClosetLifecycle')]
    if mode=='full': tasks.append(('integration.swift_db_A_to_H','ah','dedicatedDevelopmentAccountsExerciseRealSwiftAH'))
    for identity,label,method in tasks:
        if label=='ah' and not os.environ.get('FITMATCH_QA_DB_CASE_MANIFEST'):
            item(report,identity,'BLOCKED','Verified exact catalog seed manifest missing; no linked mutation started')
            continue
        output=out/('auth-swift-'+label+'.json')
        env=os.environ.copy()
        for key in required:
            env['TEST_RUNNER_'+key]=os.environ[key]
        if label=='ah': env['TEST_RUNNER_FITMATCH_QA_DB_CASE_MANIFEST']=os.environ['FITMATCH_QA_DB_CASE_MANIFEST']
        auth_run_id=str(uuid.uuid4())
        env['TEST_RUNNER_FITMATCH_QA_AUTH_RUN_ID']=auth_run_id
        env['TEST_RUNNER_FITMATCH_QA_AUTH_OUTPUT']=str(output)
        selector='FitMatchTests/FitMatchReleaseAuthenticatedTests/'+method
        bundle=out/('auth-swift-'+label+'.xcresult')
        cmd=['xcodebuild','-quiet','-project','FitMatch.xcodeproj','-scheme','FitMatch-QA','-configuration','Debug-QA',
             '-destination','platform=iOS Simulator,id='+report['simulator']['udid'],
             '-derivedDataPath',os.environ.get('FITMATCH_QA_DERIVED_DATA','/tmp/FitMatchEnvironmentBuild'),
             '-disableAutomaticPackageResolution','-parallel-testing-enabled','NO','ONLY_ACTIVE_ARCH=YES',
             '-only-testing:'+xcode_selector(selector),'-resultBundlePath',str(bundle),'test-without-building']
        code=logged(cmd,out/('auth-swift-'+label+'.log'),900,env)
        summary,tree=test_results(bundle,out,'auth-swift-'+label)
        status=xcode_status(code,summary)
        try:
            receipt=json.loads(output.read_text())
            expected=['AUTH-VERIFY','A-MANUAL','ISOLATION','B-MANUAL','C-MANUAL']
            if label=='ah':
                manifest=json.loads(Path(os.environ['FITMATCH_QA_DB_CASE_MANIFEST']).read_text())
                expected=['AUTH-VERIFY']+[c['id']+'/'+step for c in manifest['cases']
                                         for step in ['A','D','F','B','G','H','E','C','ISOLATION']]
            receipt_status=authenticated_receipt_status(receipt,auth_run_id,expected)
            if receipt_status=='FAIL': status='FAIL'
            elif receipt_status!='PASS' and status!='FAIL': status='BLOCKED'
            if matched_test_status(tree,selector)!='PASS' and status=='PASS': status='BLOCKED'
            output.write_text(redact(json.dumps(receipt,ensure_ascii=False,indent=2))+'\n')
        except (OSError,ValueError):
            if status!='FAIL': status='BLOCKED'
        item(report,identity,status,'Actual authenticated Swift subcase; exit='+str(code)+'; '+output.name)


def run_swift_cleanup(report, out, ledger_path):
    """Explicit cleanup only. No sign-up, ingestion, scoring, or broad deletion."""
    required=['FITMATCH_QA_DB_'+key for key in ('URL','PUBLIC_KEY','DEDICATED_USERS',
              'USER_A_TOKEN','USER_A_ID','USER_B_TOKEN','USER_B_ID',
              'USER_A_REFRESH_TOKEN','USER_B_REFRESH_TOKEN')]
    if not ledger_path or any(not os.environ.get(k) for k in required):
        item(report,'db.swift_cleanup','BLOCKED','Explicit Swift ledger and dedicated sessions required; no request started')
        return
    if not safe_database_url(os.environ['FITMATCH_QA_DB_URL']) or not safe_overrides(os.environ):
        item(report,'db.swift_cleanup','BLOCKED','Unsafe target; no request started')
        return
    try:
        ledger_path=Path(ledger_path).resolve(strict=True)
        ledger=json.loads(ledger_path.read_text())
        run_id=str(uuid.UUID(ledger['runID']))
        if (ledger['project']!='hnkplvyegonlhumlejst' or ledger['version']!=1
                or uuid.UUID(ledger['ownerID'])!=uuid.UUID(os.environ['FITMATCH_QA_DB_USER_A_ID'])
                or uuid.UUID(ledger['observerID'])!=uuid.UUID(os.environ['FITMATCH_QA_DB_USER_B_ID'])):
            raise ValueError('Ledger target or owner mismatch')
    except (OSError,ValueError,KeyError,TypeError):
        item(report,'db.swift_cleanup','BLOCKED','Invalid ledger or owner identity; no request started')
        return
    _,branch,_=capture(['git','branch','--show-current'])
    if branch.strip()!='QA':
        item(report,'db.swift_cleanup','BLOCKED','QA branch required; no request started')
        return
    code,raw,_=capture(['xcrun','simctl','list','devices','available','-j'])
    try:
        devices=[d for group in json.loads(raw)['devices'].values() for d in group
                 if d.get('isAvailable') and d['name'].startswith('iPhone')]
        wanted=os.environ.get('FITMATCH_QA_SIMULATOR_ID')
        selected=next((d for d in devices if d['udid']==wanted),None) if wanted else next(
            (d for d in devices if d['state']=='Booted'),devices[0] if devices else None)
        if code or not selected: raise ValueError('No simulator')
    except (ValueError,KeyError,TypeError):
        item(report,'db.swift_cleanup','BLOCKED','Available iPhone Simulator required; no request started')
        return
    output=out/'auth-swift-cleanup.json'
    env=os.environ.copy()
    for key in required: env['TEST_RUNNER_'+key]=os.environ[key]
    env['TEST_RUNNER_FITMATCH_QA_AUTH_LEDGER']=str(ledger_path)
    env['TEST_RUNNER_FITMATCH_QA_AUTH_RUN_ID']=run_id
    env['TEST_RUNNER_FITMATCH_QA_AUTH_OUTPUT']=str(output)
    selector='FitMatchTests/FitMatchReleaseAuthenticatedTests/interruptedDevelopmentRunCleansOnlyValidatedLedger'
    bundle=out/'auth-swift-cleanup.xcresult'
    cmd=['xcodebuild','-quiet','-project','FitMatch.xcodeproj','-scheme','FitMatch-QA',
         '-configuration','Debug-QA','-destination','platform=iOS Simulator,id='+selected['udid'],
         '-derivedDataPath',os.environ.get('FITMATCH_QA_DERIVED_DATA','/tmp/FitMatchEnvironmentBuild'),
         '-disableAutomaticPackageResolution','-parallel-testing-enabled','NO','ONLY_ACTIVE_ARCH=YES',
         '-only-testing:'+xcode_selector(selector),'-resultBundlePath',str(bundle),'test']
    code=logged(cmd,out/'auth-swift-cleanup.log',900,env)
    summary,tree=test_results(bundle,out,'auth-swift-cleanup')
    status=xcode_status(code,summary)
    try:
        receipt=json.loads(output.read_text()); observed=cleanup_receipt_status(receipt,run_id)
        if observed=='FAIL': status='FAIL'
        elif observed!='PASS' and status!='FAIL': status='BLOCKED'
        if status=='PASS' and matched_test_status(tree,selector)!='PASS': status='BLOCKED'
        output.write_text(redact(json.dumps(receipt,ensure_ascii=False,indent=2))+'\n')
    except (OSError,ValueError):
        if status!='FAIL': status='BLOCKED'
    item(report,'db.swift_cleanup',status,'Explicit original-run Swift ledger cleanup; exit='+str(code))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['preflight','smoke','full','report','cleanup'])
    parser.add_argument('--output',type=Path)
    parser.add_argument('--ledger',type=Path,help='Original Swift authenticated ledger; cleanup only')
    args=parser.parse_args()
    if args.ledger and args.mode!='cleanup': parser.error('--ledger is only for cleanup')
    if args.mode=='report':
        if not args.output: parser.error('report requires --output <existing run directory>')
        path=args.output/'results.json'
        report=json.loads(path.read_text()); return write_report(args.output,report)
    run_id='qa-'+dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8]
    out=(args.output or Path('/tmp/FitMatchReleaseQA')/run_id).resolve()
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error('Output must be a new or empty directory; use report mode for prior results')
    out.mkdir(parents=True,exist_ok=True,mode=0o700)
    report={'run_id':run_id,'mode':args.mode,'started_at':dt.datetime.now(dt.timezone.utc).isoformat(),'results':[]}
    try:
        if args.mode=='cleanup':
            run_swift_cleanup(report,out,args.ledger)
        else:
            preflight(report,out)
            if args.mode!='preflight':
                code=logged([sys.executable,'-m','unittest','discover','-s','scripts/tests','-p','test_release_qa*.py','-v'],out/'runner-tests.log',60)
                item(report,'tool.selftest','PASS' if code==0 and re.search(r'Ran [1-9][0-9]* tests?', (out/'runner-tests.log').read_text()) else 'FAIL','Includes controlled failure, unsafe target, zero tests, corpus drift')
                code=logged([sys.executable,'scripts/test_release_qa_db.py','-v'],out/'db-runner-tests.log',60)
                item(report,'tool.db_selftest','PASS' if code==0 and re.search(r'Ran [1-9][0-9]* tests?', (out/'db-runner-tests.log').read_text()) else 'FAIL','Dedicated DB safety tests; not live RPC proof')
                run_xcode(report,out,args.mode)
            run_db(report,out,args.mode)
            # Missing required proof must not become green through omitted test groups.
            if args.mode=='full':
                remaining={
                    'integration.swift_db_A_to_H':'Dedicated authentication or verified catalog seeds unavailable; see authenticated harness receipt',
                    'integration.cross_provider_3x3':'Synthetic 756-case execution is not live retailer/group/semantic authorization evidence; verified seed bindings required',
                    'sequence.complete_chains':'Local owner chains and mounted synthetic selection are covered; complete authenticated DB chains remain unverified'}
                present={r['id'] for r in report['results']}
                for identity,detail in remaining.items():
                    if identity not in present: item(report,identity,'BLOCKED',detail)
    except KeyboardInterrupt:
        item(report,'run.interrupted','BLOCKED','Interrupted; inspect DB ledger before cleanup')
    except Exception as e:
        item(report,'tool.exception','FAIL',redact(str(e)))
    finally:
        result=write_report(out,report)
        print('REPORT: '+str(out/'report.md'),flush=True)
    return result

if __name__=='__main__': sys.exit(main())
