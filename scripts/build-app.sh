#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox
bin_dir=$(swift build -c release --show-bin-path --disable-sandbox)
app="$PWD/dist/MIDI Clock.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
iconset="$PWD/.build/AppIcon.iconset"
mkdir -p "$iconset"
for icon_size in 16 32 128 256 512; do
    sips -z "$icon_size" "$icon_size" Resources/AppIcon.png --out "$iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
    retina_size=$((icon_size * 2))
    sips -z "$retina_size" "$retina_size" Resources/AppIcon.png --out "$iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
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
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built: $app"
