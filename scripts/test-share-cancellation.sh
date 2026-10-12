#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/fitmatch-share-cancellation.XXXXXX)"
# Compile the actual UIKit controller and shared handoff into an isolated test
# bundle. Only access control and App Group configuration change in the copy;
# persistence, callbacks, Close, and button handlers remain production code.
python3 - "$repo" "$work" <<'PY'
from pathlib import Path
import sys
r,w=map(Path,sys.argv[1:])
for name in ['FitMatchSharedURLHandoff.swift','FitMatchProductURLRouting.swift','FitMatchShareAttachmentExtractor.swift']:
    (w/name).write_bytes((r/'Shared'/name).read_bytes())
s=(r/'FitMatchShareExtension/ShareViewController.swift').read_text()
s=s.replace('private ', '').replace('group.com.ljy4337.fitmatch', 'group.com.ljy4337.fitmatch.shareCancellationRegression')
(w/'ShareViewController.swift').write_text(s)
(w/'ShareCancellationTests.swift').write_bytes((r/'scripts/tests/share-cancellation/ShareCancellationTests.swift').read_bytes())
PY
ruby - "$work" <<'RUBY'
require 'xcodeproj'
w=ARGV.fetch(0)
p=Xcodeproj::Project.new(File.join(w,'ShareCancellation.xcodeproj'))
t=p.new_target(:unit_test_bundle,'ShareCancellationTests',:ios,'17.0')
Dir.glob(File.join(w,'*.swift')).each { |f| t.add_file_references([p.main_group.new_file(f)]) }
t.build_configurations.each do |c|
 c.build_settings['GENERATE_INFOPLIST_FILE']='YES'
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='com.ljy4337.fitmatch.shareCancellationRegressionTests'
 c.build_settings['SWIFT_VERSION']='5.0'
 c.build_settings['CODE_SIGNING_ALLOWED']='NO'
 c.build_settings['TARGETED_DEVICE_FAMILY']='1,2'
end
s=Xcodeproj::XCScheme.new
s.add_build_target(t)
s.add_test_target(t)
s.save_as(p.path,'ShareCancellationTests',true)
p.save
RUBY
xcodebuild test -quiet -project "$work/ShareCancellation.xcodeproj" \
  -scheme ShareCancellationTests -destination "${FITMATCH_SHARE_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17}" \
  -derivedDataPath "$work/DerivedData" -resultBundlePath "$work/result.xcresult" \
  CODE_SIGNING_ALLOWED=NO
