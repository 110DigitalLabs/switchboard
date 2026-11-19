#!/usr/bin/env bash
# Builds Switchboard from this checkout and installs it over
# /Applications/Switchboard.app, for trying changes before a release.
# Nothing is notarized, tagged or uploaded.
#
# It is signed with the same Developer ID as releases, so macOS keeps the
# permissions already granted (microphone, speech recognition, folders).
# An ad-hoc signature would make macOS ask again after every build.
#
# Optional environment:
#   DEVELOPER_ID_APPLICATION  signing identity; defaults to the first
#                             "Developer ID Application" in the keychain
#
# Switchboard must be quit before installing: the agents in its terminals
# run inside it. The build happens first, so you can quit while it runs.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "install-local.sh: $*" >&2
    exit 1
}

dest="/Applications/Switchboard.app"
build="dist/local"
log="$build/xcodebuild.log"

identity=${DEVELOPER_ID_APPLICATION:-$(security find-identity -v -p codesigning \
    | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -n 1)}
[[ -n "$identity" ]] || fail "no Developer ID Application identity in the keychain (set DEVELOPER_ID_APPLICATION)"
team=$(sed -nE 's/.*\(([A-Z0-9]+)\)$/\1/p' <<<"$identity")
[[ -n "$team" ]] || fail "could not read the team ID from \"$identity\""

mkdir -p "$build"
echo "==> Building Release, signed as $identity"
xcodegen generate >/dev/null
if ! xcodebuild build \
    -project Switchboard.xcodeproj \
    -scheme Switchboard \
    -configuration Release \
    -derivedDataPath "$build/DerivedData" \
    -skipPackagePluginValidation \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$identity" \
    DEVELOPMENT_TEAM="$team" \
    ENABLE_HARDENED_RUNTIME=YES \
    >"$log" 2>&1; then
    grep -E "error:" "$log" >&2 || tail -n 20 "$log" >&2
    fail "build failed; full log in $log"
fi
app="$build/DerivedData/Build/Products/Release/Switchboard.app"
[[ -d "$app" ]] || fail "build produced no $app"
codesign --verify --deep --strict "$app"

# -a: macOS pgrep otherwise skips its own ancestors, which is exactly the
# copy running this script when it runs in a Switchboard terminal.
if pgrep -af "^$dest/Contents/MacOS/Switchboard" >/dev/null; then
    echo
    echo "Built $app"
    fail "Switchboard is running from $dest; quit it, then run this again (the build is cached)"
fi

echo "==> Installing to $dest"
staging="$dest.installing"
rm -rf "$staging"
ditto "$app" "$staging"
rm -rf "$dest"
mv "$staging" "$dest"
echo "Installed $(defaults read "$dest/Contents/Info" CFBundleShortVersionString) from $(git rev-parse --short HEAD)$(git diff --quiet HEAD || echo ' plus uncommitted changes')"
