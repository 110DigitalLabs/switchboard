#!/usr/bin/env bash
# Regenerates Sources/Switchboard/Assets.xcassets/AppIcon.appiconset from
# scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

set_dir=Sources/Switchboard/Assets.xcassets/AppIcon.appiconset
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swiftc -O scripts/make-icon.swift -o "$work/make-icon"
"$work/make-icon" "$work/icon-1024.png"

mkdir -p "$set_dir"
entries=()
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((points * scale))
        name="icon_${points}x${points}@${scale}x.png"
        sips -z "$px" "$px" "$work/icon-1024.png" --out "$set_dir/$name" >/dev/null
        entries+=("    { \"idiom\" : \"mac\", \"size\" : \"${points}x${points}\", \"scale\" : \"${scale}x\", \"filename\" : \"$name\" }")
    done
done
cat >"$set_dir/Contents.json" <<JSON
{
  "images" : [
$(IFS=$'\n'; printf '%s\n' "${entries[@]}" | sed '$!s/$/,/')
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
cat >Sources/Switchboard/Assets.xcassets/Contents.json <<JSON
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
echo "Wrote $set_dir"
