#!/bin/bash
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
audit="$root/scripts/audit-app-store-archive.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
archive="$tmp/Test.xcarchive"
app="$archive/Products/Applications/FitMatch.app"
ext="$app/PlugIns/FitMatchShareExtension.appex"
mkdir -p "$ext"
write_plist() {
    /usr/libexec/PlistBuddy -c "Clear dict" "$1" >/dev/null
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $2" "$1"
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $3" "$1"
}
write_plist "$app/Info.plist" 2.3 19
write_plist "$ext/Info.plist" 2.3 19
run() {
    set +e
    bash "$audit" "$@" > "$tmp/output" 2>&1
    result=$?
    set -e
}
run
[[ $result == 2 ]]
run "$archive"
[[ $result == 2 ]]
run "$archive" '' 19
[[ $result == 2 ]]
run "$archive" 2.3 19
# Synthetic bundle has no signature/manifests: overall success MUST remain blocked.
[[ $result == 1 ]]
grep -q 'PASS: app marketing version' "$tmp/output"
grep -q 'PASS: app build number' "$tmp/output"
grep -q 'PASS: share extension marketing version' "$tmp/output"
grep -q 'PASS: share extension build number' "$tmp/output"
grep -q 'FAIL: app signature' "$tmp/output"
run "$archive" 2.4 20
[[ $result == 1 ]]
grep -q 'FAIL: app marketing version' "$tmp/output"
grep -q 'FAIL: app build number' "$tmp/output"
write_plist "$ext/Info.plist" 2.2 18
run "$archive" 2.3 19
[[ $result == 1 ]]
grep -q 'PASS: app marketing version' "$tmp/output"
grep -q 'FAIL: share extension marketing version' "$tmp/output"
grep -q 'FAIL: share extension build number' "$tmp/output"
echo 'PASS: 6 archive argument/version cases; synthetic archive remains rejected'
