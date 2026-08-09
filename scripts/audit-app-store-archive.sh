#!/bin/bash

set -u

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /path/to/FitMatch.xcarchive" >&2
    exit 2
fi

archive_path=$1
app_path="$archive_path/Products/Applications/FitMatch.app"
extension_path="$app_path/PlugIns/FitMatchShareExtension.appex"
app_plist="$app_path/Info.plist"
extension_plist="$extension_path/Info.plist"
issue_count=0

fail() {
    echo "FAIL: $1" >&2
    issue_count=$((issue_count + 1))
}

pass() {
    echo "PASS: $1"
}

require_distribution_signature() {
    local bundle_path=$1
    local description=$2
    local signature_details

    if ! /usr/bin/codesign --verify --deep --strict "$bundle_path" >/dev/null 2>&1; then
        fail "$description is missing or invalid"
        return
    fi

    signature_details=$(/usr/bin/codesign -dv --verbose=4 "$bundle_path" 2>&1)
    if [[ "$signature_details" == *"Authority=Apple Distribution:"* ]] \
        || [[ "$signature_details" == *"Authority=iPhone Distribution:"* ]]; then
        pass "$description uses an App Store distribution identity"
    else
        fail "$description is not signed with an App Store distribution identity"
    fi
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

require_path() {
    if [[ -e "$1" ]]; then
        pass "$2"
    else
        fail "$2"
    fi
}

require_plist_value() {
    local plist_path=$1
    local key=$2
    local expected=$3
    local description=$4
    local actual
    actual=$(plist_value "$plist_path" "$key")
    if [[ "$actual" == "$expected" ]]; then
        pass "$description"
    else
        fail "$description (expected=$expected actual=${actual:-missing})"
    fi
}

require_path "$archive_path" "archive exists"
require_path "$app_path" "app bundle exists"
require_path "$extension_path" "share extension exists"
require_path "$app_plist" "app Info.plist exists"
require_path "$extension_plist" "share extension Info.plist exists"

if [[ -f "$app_plist" ]]; then
    require_plist_value "$app_plist" CFBundleIdentifier "com.ljy4337.fitmatch" "app bundle identifier"
    require_plist_value "$app_plist" CFBundleShortVersionString "1.0" "app marketing version"
    require_plist_value "$app_plist" CFBundleVersion "4" "app build number"
    require_plist_value "$app_plist" CFBundleURLTypes:0:CFBundleURLName "com.ljy4337.fitmatch" "URL type identifier"
    require_plist_value "$app_plist" CFBundleURLTypes:0:CFBundleURLSchemes:0 "fitmatch" "URL scheme"

    privacy_url=$(plist_value "$app_plist" FitMatchPrivacyPolicyURL)
    support_url=$(plist_value "$app_plist" FitMatchSupportURL)

    if [[ "$privacy_url" == https://* ]]; then
        pass "public privacy policy URL configured"
    else
        fail "public privacy policy URL is missing or not HTTPS"
    fi
    if [[ "$support_url" == https://* ]]; then
        pass "public support URL configured"
    else
        fail "public support URL is missing or not HTTPS"
    fi
fi

if [[ -f "$extension_plist" ]]; then
    require_plist_value "$extension_plist" CFBundleIdentifier "com.ljy4337.fitmatch.shareextension" "share extension bundle identifier"
    require_plist_value "$extension_plist" CFBundleShortVersionString "1.0" "share extension marketing version"
    require_plist_value "$extension_plist" CFBundleVersion "4" "share extension build number"
fi

require_path "$app_path/PrivacyInfo.xcprivacy" "app Privacy Manifest"
require_path "$extension_path/PrivacyInfo.xcprivacy" "share extension Privacy Manifest"
require_path "$archive_path/dSYMs/FitMatch.app.dSYM" "app dSYM"
require_path "$archive_path/dSYMs/FitMatchShareExtension.appex.dSYM" "share extension dSYM"

if [[ -d "$app_path" ]]; then
    require_distribution_signature "$app_path" "app signature"
fi
if [[ -d "$extension_path" ]]; then
    require_distribution_signature "$extension_path" "share extension signature"
fi

if [[ -f "$app_path/FitMatch" ]]; then
    architecture=$(/usr/bin/file "$app_path/FitMatch")
    if [[ "$architecture" == *"arm64"* ]]; then
        pass "app executable contains arm64"
    else
        fail "app executable does not contain arm64"
    fi
else
    fail "app executable exists"
fi

if [[ -f "$app_path/PrivacyInfo.xcprivacy" ]]; then
    if /usr/bin/plutil -lint "$app_path/PrivacyInfo.xcprivacy" >/dev/null; then
        pass "app Privacy Manifest plist is valid"
    else
        fail "app Privacy Manifest plist is invalid"
    fi
fi

if [[ -f "$extension_path/PrivacyInfo.xcprivacy" ]]; then
    if /usr/bin/plutil -lint "$extension_path/PrivacyInfo.xcprivacy" >/dev/null; then
        pass "share extension Privacy Manifest plist is valid"
    else
        fail "share extension Privacy Manifest plist is invalid"
    fi
fi

if [[ $issue_count -ne 0 ]]; then
    echo "RESULT: failed ($issue_count issue(s))" >&2
    exit 1
fi

echo "RESULT: passed"
