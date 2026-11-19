#!/usr/bin/env bash
# Publishes the zip that release.sh built: tags v<version>, creates the GitHub
# release, and bumps the cask both here and in the Homebrew tap, which is what
# `brew upgrade` and the in-app updater actually read. Fails unless Homebrew
# ends up seeing the new version.
#
# Usage: scripts/publish.sh <release-notes.md>
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "publish.sh: $*" >&2
    exit 1
}

notes=${1:-}
[[ -n "$notes" && -f "$notes" ]] || fail "usage: scripts/publish.sh <release-notes.md>"

version=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' project.yml | head -n 1)
[[ -n "$version" ]] || fail "could not read MARKETING_VERSION from project.yml"
zip="dist/$version/Switchboard-$version.zip"
[[ -f "$zip" ]] || fail "$zip not found; run scripts/release.sh first"

[[ "$(git branch --show-current)" == main ]] || fail "not on main"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean"

tap="110digitallabs/tap"
tap_dir=$(brew --repo "$tap")
[[ -d "$tap_dir/.git" ]] || fail "Homebrew tap $tap is not tapped (brew tap $tap)"
[[ -z "$(git -C "$tap_dir" status --porcelain)" ]] || fail "$tap_dir has uncommitted changes"

sha=$(shasum -a 256 "$zip" | awk '{print $1}')
echo "==> Switchboard $version ($sha)"

bump_cask() {
    sed -i '' -E \
        -e "s/^([[:space:]]*version )\"[^\"]*\"/\1\"$version\"/" \
        -e "s/^([[:space:]]*sha256 )\"[^\"]*\"/\1\"$sha\"/" "$1"
    grep -q "version \"$version\"" "$1" && grep -q "sha256 \"$sha\"" "$1" || fail "could not bump $1"
}

echo "==> Tagging and pushing"
git push -q origin main
git rev-parse -q --verify "refs/tags/v$version" >/dev/null || git tag "v$version"
git push -q origin "v$version"

echo "==> GitHub release"
if gh release view "v$version" >/dev/null 2>&1; then
    echo "release v$version already exists; leaving it as is"
else
    gh release create "v$version" "$zip" --title "Switchboard $version" --notes-file "$notes"
fi

echo "==> Uploaded zip matches"
url="https://github.com/110DigitalLabs/switchboard/releases/download/v$version/Switchboard-$version.zip"
remote_sha=$(curl -fsSL "$url" | shasum -a 256 | awk '{print $1}')
[[ "$remote_sha" == "$sha" ]] || fail "downloaded zip has sha256 $remote_sha, expected $sha"

echo "==> Cask in this repo"
bump_cask Casks/switchboard.rb
if [[ -n "$(git status --porcelain Casks/switchboard.rb)" ]]; then
    git commit -q -m "Cask: Switchboard $version" Casks/switchboard.rb
    git push -q origin main
fi

echo "==> Cask in the Homebrew tap"
git -C "$tap_dir" pull -q --ff-only
bump_cask "$tap_dir/Casks/switchboard.rb"
if [[ -n "$(git -C "$tap_dir" status --porcelain)" ]]; then
    git -C "$tap_dir" commit -q -m "Switchboard $version" Casks/switchboard.rb
    git -C "$tap_dir" push -q
fi

echo "==> Homebrew sees it"
brew update -q >/dev/null
seen=$(brew info --cask --json=v2 switchboard | sed -nE 's/.*"version": *"([^"]+)".*/\1/p' | head -n 1)
[[ "$seen" == "$version" ]] || fail "Homebrew reports switchboard $seen, expected $version"

echo
echo "Published Switchboard $version: $url"
