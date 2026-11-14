#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

app="$PWD/dist/MIDI Clock Controller.app"
[[ -d "$app" ]] || { echo "Run zsh scripts/build-app.sh first." >&2; exit 1; }
codesign --verify --deep --strict "$app"
sparkle="$PWD/.build/artifacts/sparkle/Sparkle"
[[ -x "$sparkle/bin/generate_appcast" ]] || { echo "Resolve the Sparkle package first." >&2; exit 1; }
public_key=$("$sparkle/bin/generate_keys" --account local.midi-clock-controller -p)
bundled_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")
[[ "$public_key" == "$bundled_key" ]] || { echo "The signing key does not match this app's update public key." >&2; exit 1; }

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
architecture=$(lipo -archs "$app/Contents/MacOS/MIDIClockController")
case "$architecture" in
    arm64|x86_64) ;;
    "x86_64 arm64"|"arm64 x86_64") architecture=universal ;;
    *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
esac
output="$PWD/dist/release"
mkdir -p "$output"
stage=$(mktemp -d "$PWD/dist/update-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
filename="MIDI-Clock-Controller-v${version}-macOS-${architecture}.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$filename"
notes="${1:-$PWD/docs/releases/v${version}.md}"
python3 - "$notes" "$stage/${filename%.zip}.html" <<'PY'
from pathlib import Path
import html, sys
source = Path(sys.argv[1])
notes = source.read_text() if source.is_file() else ""
warning = "Installing this update stops local MIDI playback and restarts the app.\n安装更新将停止本机 MIDI 播放并重新启动应用。"
Path(sys.argv[2]).write_text("<p>" + html.escape(warning).replace("\n", "<br>") + "</p><pre style='white-space:pre-wrap'>" + html.escape(notes) + "</pre>")
PY
"$sparkle/bin/generate_appcast" --account local.midi-clock-controller \
    --download-url-prefix "https://github.com/lenuxo/midi-clock-controller/releases/download/v${version}/" \
    --link "https://github.com/lenuxo/midi-clock-controller/releases/tag/v${version}" \
    --embed-release-notes --maximum-deltas 0 "$stage"
cp "$stage/$filename" "$stage/appcast.xml" "$output/"
(cd "$output" && shasum -a 256 "$filename" > "$filename.sha256")
echo "Upload together to the corresponding GitHub Release:"
echo "$output/$filename"
echo "$output/appcast.xml"
