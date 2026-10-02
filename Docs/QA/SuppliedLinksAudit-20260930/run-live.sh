#!/bin/bash
export TEST_RUNNER_FITMATCH_RELEASE_URLS='/Users/jinyoung/Developer/FitMatchLocal/FitMatch/Docs/QA/SuppliedLinksAudit-20260930/urls.txt'
export TEST_RUNNER_FITMATCH_RELEASE_OUTPUT='/Users/jinyoung/Developer/FitMatchLocal/FitMatch/Docs/QA/SuppliedLinksAudit-20260930/results.json'
xcodebuild -quiet -project FitMatch.xcodeproj -scheme FitMatch -destination 'platform=iOS Simulator,id=03BAF093-552E-4E53-ABFB-7DE0653BE676' -derivedDataPath /tmp/FitMatchBuild8Debug -disableAutomaticPackageResolution -parallel-testing-enabled NO -only-testing:FitMatchTests/FitMatchReleaseLiveProductAuditTests -resultBundlePath /tmp/FitMatchSuppliedLinksLive20260930.xcresult test > /tmp/FitMatchSuppliedLinksLive20260930.log 2>&1
