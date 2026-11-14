#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox
bin_dir=$(swift build -c release --show-bin-path --disable-sandbox)
app="$PWD/dist/MIDI Clock Controller.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
sparkle="$PWD/.build/artifacts/sparkle/Sparkle"
ditto "$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp -R "$bin_dir/MIDIClockController_AppLocalization.bundle" "$app/Contents/Resources/"
cp -R "$bin_dir/MIDIClockController_MIDIClockController.bundle" "$app/Contents/Resources/"
for language in zh-Hans en; do
    mkdir -p "$app/Contents/Resources/$language.lproj"
    cp "Sources/AppLocalization/Resources/$language.lproj/Localizable.strings" "$app/Contents/Resources/$language.lproj/"
    cp "Resources/$language.lproj/InfoPlist.strings" "$app/Contents/Resources/$language.lproj/"
done
mkdir -p "$app/Contents/Resources/ThirdPartyLicenses"
cp "$sparkle/LICENSE" "$app/Contents/Resources/ThirdPartyLicenses/Sparkle-LICENSE.txt"
cp LICENSE "$app/Contents/Resources/ThirdPartyLicenses/MIDI-Clock-Controller-LICENSE.txt"
cp COPYING.md "$app/Contents/Resources/ThirdPartyLicenses/MIDI-Clock-Controller-COPYING.md"
cp Sources/CLink/vendor/link/LICENSE.md "$app/Contents/Resources/ThirdPartyLicenses/Ableton-Link-LICENSE.md"
cp Sources/CLink/vendor/link/GNU-GPL-v2.0.md "$app/Contents/Resources/ThirdPartyLicenses/GNU-GPL-v2.0.md"
cp Sources/CLink/vendor/asio/LICENSE_1_0.txt "$app/Contents/Resources/ThirdPartyLicenses/Asio-LICENSE.txt"
cp Sources/MIDIClockController/Resources/Fonts/DSEG-LICENSE.txt "$app/Contents/Resources/ThirdPartyLicenses/DSEG-LICENSE.txt"
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
<key>CFBundleName</key><string>MIDI Clock Controller</string>
<key>CFBundleDisplayName</key><string>MIDI Clock Controller</string>
<key>CFBundleIdentifier</key><string>local.midi-clock-controller</string>
<key>CFBundleExecutable</key><string>MIDIClockController</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
<key>CFBundleShortVersionString</key><string>0.1.10</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSLocalNetworkUsageDescription</key><string>Discover Ableton Link peers and share musical tempo and beat timing on your local network.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(cat Resources/UpdatePublicKey.txt)" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUFeedURL string https://github.com/lenuxo/midi-clock-controller/releases/latest/download/appcast.xml' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool false' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUAllowsAutomaticUpdates bool false' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUAutomaticallyUpdate bool false' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUEnableSystemProfiling bool false' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUVerifyUpdateBeforeExtraction bool true' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SURequireSignedFeed bool true' "$app/Contents/Info.plist"
if ! otool -l "$app/Contents/MacOS/MIDIClockController" | rg -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/MIDIClockController"
fi
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built: $app"
