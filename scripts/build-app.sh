#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox
bin_dir=$(swift build -c release --show-bin-path --disable-sandbox)
app="$PWD/dist/MIDI Clock.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/MIDIClockController" "$app/Contents/MacOS/.MIDIClockController.next"
mv -f "$app/Contents/MacOS/.MIDIClockController.next" "$app/Contents/MacOS/MIDIClockController"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MIDI Clock</string>
<key>CFBundleDisplayName</key><string>MIDI Clock</string>
<key>CFBundleIdentifier</key><string>local.midi-clock-controller</string>
<key>CFBundleExecutable</key><string>MIDIClockController</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built: $app"
