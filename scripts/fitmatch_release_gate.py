#!/usr/bin/env python3
"""Strict local QA promotion gate; reuses existing runners and Xcode tests."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_qa', ROOT / 'scripts/release_qa.py')
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
REQUIRED = (
    'gate.branch', 'gate.clean_tree', 'gate.diff', 'gate.protected_scroll',
    'gate.runner_tests', 'gate.archive_tests', 'environment.qa_target',
    'safety.db_target', 'data.freeze', 'policy.expectations',
    'app.build_execution', 'app.discovery', 'parser.live_execution',
    'parser.live.musinsa', 'parser.live.uniqlo', 'parser.live.zara',
    'db.contract', 'db.swift_manual', 'integration.swift_db_A_to_H',
    'gate.ui_fixture', 'gate.ui_authenticated_A_E',
)
SCROLL = ('hidesBottomTabBarOnScroll', 'tracksTabBarVisibilityOnScroll', 'hidesTopChromeOnScroll')


def overall(records):
    ids = [row['id'] for row in records]
    states = [row['status'] for row in records]
    if len(ids) != len(set(ids)) or any(s not in ('PASS', 'FAIL', 'BLOCKED', 'NOT RUN') for s in states):
        return 'FAIL'
    if 'FAIL' in states:
        return 'FAIL'
    if 'BLOCKED' in states:
        return 'BLOCKED'
    if 'NOT RUN' in states or set(REQUIRED) - set(ids):
        return 'NOT RUN'
    return 'PASS'


def protected_diff(names, diff):
    return ('FitMatch/Components/TabBarScrollVisibilityModifier.swift' in names
            or any(name in diff for name in SCROLL))


def write_summary(report, out):
    report['overall'] = overall(report['results'])
    (out / 'release-gate.json').write_text(qa.redact(json.dumps(report, ensure_ascii=False, indent=2)) + '\n')
    lines = ['# FitMatch Release Gate', '', 'Overall: ' + report['overall'],
             'HEAD: ' + report.get('head', 'unknown'),
             'Database: development hnkplvyegonlhumlejst; Production mutation 0', '',
             '| Check | Status | Evidence |', '|---|---|---|']
    for row in report['results']:
        detail = str(row.get('detail', '')).replace('|', '/').replace('\n', ' ')
        lines.append('| ' + row['id'] + ' | ' + row['status'] + ' | ' + qa.redact(detail) + ' |')
    lines += ['', 'USER CHECK / NOT AUTOMATED: physical iPhone UX, design and Apple submission.',
              'Fixture UI and synthetic owner tests do not prove authenticated A-E screen journeys.']
    (out / 'release-gate.md').write_text('\n'.join(lines) + '\n')
    print('RELEASE GATE = ' + report['overall'])
    print(str(out / 'release-gate.md'))
    return 0 if report['overall'] == 'PASS' else 1 if report['overall'] == 'FAIL' else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    out = args.output or Path('/private/tmp/FitMatchReleaseGate') / ('gate-' + str(uuid.uuid4()))
    out = out.resolve()
    if out == ROOT or ROOT in out.parents or (out.exists() and any(out.iterdir())):
        parser.error('Use a new, empty output directory outside the checkout')
    out.mkdir(parents=True, exist_ok=True)
    os.chdir(ROOT)
    report = {'run_id': str(uuid.uuid4()), 'mode': 'release_gate',
              'started_at': datetime.now(timezone.utc).isoformat(), 'results': []}
    try:
        code, head, _ = qa.capture(['git', 'rev-parse', 'HEAD'])
        report['head'] = head.strip() if code == 0 else 'unknown'
        code, branch, _ = qa.capture(['git', 'branch', '--show-current'])
        qa.item(report, 'gate.branch', 'PASS' if code == 0 and branch.strip() == 'QA' else 'BLOCKED',
                'QA required; actual=' + branch.strip())
        code, dirty, _ = qa.capture(['git', 'status', '--porcelain=v1', '--untracked-files=all'])
        qa.item(report, 'gate.clean_tree', 'PASS' if code == 0 and not dirty.strip() else 'BLOCKED',
                'Exact committed source required; dirty file count=' + str(len(dirty.splitlines())))
        code, _, error = qa.capture(['git', 'diff', '--check', 'main', 'HEAD'])
        qa.item(report, 'gate.diff', 'PASS' if code == 0 else 'FAIL', error or 'main..HEAD diff check')
        nc, names, ne = qa.capture(['git', 'diff', '--name-only', 'main', 'HEAD'])
        dc, diff, de = qa.capture(['git', 'diff', 'main', 'HEAD', '--', 'FitMatch', 'FitMatchShareExtension'])
        qa.item(report, 'gate.protected_scroll',
                'FAIL' if nc or dc or protected_diff(names, diff) else 'PASS',
                ne or de or 'Protected file and modifier call sites compared with main')
        if any(r['status'] != 'PASS' for r in report['results']):
            return write_summary(report, out)
        for identity, cmd, log in (
            ('gate.runner_tests', [sys.executable, '-B', '-m', 'unittest', 'discover',
                                   '-s', 'scripts/tests', '-p', 'test*release*.py', '-v'], 'runner-tests.log'),
            ('gate.archive_tests', ['bash', 'scripts/tests/test-audit-app-store-archive.sh'], 'archive-tests.log'),
        ):
            code = qa.logged(cmd, out / log, 180)
            qa.item(report, identity, 'PASS' if code == 0 else 'FAIL', 'exit=' + str(code) + '; ' + log)
        qa.preflight(report, out)
        if not next((r['status'] == 'PASS' for r in report['results'] if r['id'] == 'safety.db_target'), False):
            return write_summary(report, out)
        qa.run_xcode(report, out, 'smoke')
        qa.run_db(report, out, 'full')
        if not any(r['id'] == 'integration.swift_db_A_to_H' for r in report['results']):
            qa.item(report, 'integration.swift_db_A_to_H', 'BLOCKED',
                    'Normal dedicated sessions and verified exact catalog seed manifest required')
        if report.get('app_test_summary', {}).get('passedTests'):
            bundle = out / 'ui-fixture.xcresult'
            command = ['xcodebuild', '-quiet', '-project', 'FitMatch.xcodeproj', '-scheme', 'FitMatch-QA',
                       '-configuration', 'Debug-QA', '-destination',
                       'platform=iOS Simulator,id=' + report['simulator']['udid'],
                       '-derivedDataPath', os.environ.get('FITMATCH_QA_DERIVED_DATA', '/tmp/FitMatchEnvironmentBuild'),
                       '-disableAutomaticPackageResolution', '-parallel-testing-enabled', 'NO',
                       '-only-testing:FitMatchUITests/FitMatchOnboardingUITests',
                       '-only-testing:FitMatchUITests/FitMatchReleaseCurrentUIAuditTests',
                       '-resultBundlePath', str(bundle), 'test']
            code = qa.logged(command, out / 'ui-fixture.log', 900)
            summary, _ = qa.test_results(bundle, out, 'ui-fixture')
            qa.item(report, 'gate.ui_fixture', qa.xcode_status(code, summary),
                    'Fixture screens only; exit=' + str(code) + '; ' + str(summary))
        else:
            qa.item(report, 'gate.ui_fixture', 'BLOCKED', 'QA test host unavailable')
        qa.item(report, 'gate.ui_authenticated_A_E', 'BLOCKED',
                'Existing live UI helpers do not prove full A-E; dedicated normal app login and exact-case screen evidence still required')
    except KeyboardInterrupt:
        qa.item(report, 'gate.interrupted', 'BLOCKED', 'Interrupted; unfinished work is not PASS')
    except Exception as error:
        qa.item(report, 'gate.exception', 'BLOCKED', qa.redact(str(error)))
    return write_summary(report, out)


if __name__ == '__main__':
    sys.exit(main())
