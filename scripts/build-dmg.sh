#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

app="$PWD/dist/MIDI Clock.app"
[[ -d "$app" ]] || { echo "Run zsh scripts/build-app.sh first." >&2; exit 1; }
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
architecture=$(lipo -archs "$app/Contents/MacOS/MIDIClockController")
case "$architecture" in
    arm64|x86_64) ;;
    "x86_64 arm64"|"arm64 x86_64") architecture=universal ;;
    *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
esac
output="$PWD/dist/release"
mkdir -p "$output"
stage=$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/MIDI Clock.app"
ln -s /Applications "$stage/Applications"
filename="MIDI-Clock-v${version}-macOS-${architecture}.dmg"
hdiutil create -volname "MIDI Clock $version" -srcfolder "$stage" -ov -format UDZO "$output/$filename"
hdiutil verify "$output/$filename"
(cd "$output" && shasum -a 256 "$filename" > "$filename.sha256")
echo "Built: $output/$filename"
