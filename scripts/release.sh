#!/usr/bin/env bash
# Builds a Developer ID signed, notarized and stapled Switchboard-<version>.zip
# for the Homebrew cask, and prints its sha256.
#
# Required environment:
#   DEVELOPER_ID_APPLICATION  signing identity, e.g. "Developer ID Application: Jane Doe (ABCDE12345)"
#   TEAM_ID                   Apple developer team ID, e.g. ABCDE12345
#   NOTARY_PROFILE            keychain profile made with `xcrun notarytool store-credentials`
#
# The version comes from MARKETING_VERSION in project.yml; this script never
# bumps it, tags, or uploads anything.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "release.sh: $*" >&2
    exit 1
}

missing=()
for var in DEVELOPER_ID_APPLICATION TEAM_ID NOTARY_PROFILE; do
    if [[ -z "${!var:-}" ]]; then
        missing+=("$var")
    fi
done
if ((${#missing[@]} > 0)); then
    fail "missing environment variable(s): ${missing[*]} (see the header of this script)"
fi

for tool in xcodegen xcodebuild ditto xcrun shasum; do
    command -v "$tool" >/dev/null || fail "$tool not found on PATH"
done

version=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' project.yml | head -n 1)
[[ -n "$version" ]] || fail "could not read MARKETING_VERSION from project.yml"

dist="dist/$version"
archive="$dist/Switchboard.xcarchive"
export_dir="$dist/export"
app="$export_dir/Switchboard.app"
zip="$dist/Switchboard-$version.zip"
log="$dist/xcodebuild.log"

rm -rf "$dist"
mkdir -p "$dist"

echo "==> Switchboard $version"
xcodegen generate >/dev/null

echo "==> Archiving (Release, Developer ID, hardened runtime)"
if ! xcodebuild archive \
    -project Switchboard.xcodeproj \
    -scheme Switchboard \
    -configuration Release \
    -archivePath "$archive" \
    -derivedDataPath "$dist/DerivedData" \
    -skipPackagePluginValidation \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    >"$log" 2>&1; then
    grep -E "error:" "$log" >&2 || tail -n 20 "$log" >&2
    fail "archive failed; full log in $log"
fi

echo "==> Exporting"
export_options="$dist/ExportOptions.plist"
cat >"$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>${DEVELOPER_ID_APPLICATION}</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
</dict>
</plist>
PLIST
if ! xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$export_options" \
    >>"$log" 2>&1; then
    grep -E "error:" "$log" >&2 || tail -n 20 "$log" >&2
    fail "export failed; full log in $log"
fi
[[ -d "$app" ]] || fail "export produced no $app"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$app"
# Captured first: with pipefail, grep -q closing the pipe early fails codesign.
signature=$(codesign -dvv "$app" 2>&1)
grep -q "flags=.*runtime" <<<"$signature" || fail "hardened runtime is not enabled on $app"
grep -q "Authority=Developer ID Application" <<<"$signature" || fail "$app is not signed with a Developer ID"

echo "==> Notarizing"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

sha=$(shasum -a 256 "$zip" | awk '{print $1}')
echo
echo "Built $zip"
echo "version \"$version\""
echo "sha256 \"$sha\""
