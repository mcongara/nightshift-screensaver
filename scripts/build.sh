#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
language="${1:-tr}"
version=$(cat VERSION)
case "$language" in
    tr) flags=(-D TURKISH) ;;
    en) flags=(-D ENGLISH) ;;
    all)
        bash scripts/build.sh tr
        bash scripts/build.sh en
        exit 0 ;;
    *) printf 'Usage: bash scripts/build.sh [tr|en|all]\n' >&2; exit 1 ;;
esac
output="$PWD/build/$language"
mkdir -p build/module-cache "$output/NightShift.saver/Contents/MacOS"
swiftc "${flags[@]}" -module-cache-path "$PWD/build/module-cache" -swift-version 5 -O \
  -target arm64-apple-macosx15.0 -emit-library -module-name NightShift \
  -framework AppKit -framework ScreenSaver Sources/Localization.swift Sources/Canvas.swift Sources/Options.swift Sources/Saver.swift \
  -o "$output/NightShift.saver/Contents/MacOS/NightShift"
cat > "$output/NightShift.saver/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.nightshift.saver</string>
<key>CFBundleName</key><string>Night Shift</string>
<key>CFBundleExecutable</key><string>NightShift</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>NSPrincipalClass</key><string>NightShiftView</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$output/NightShift.saver"
# Swift executable top-level code must live in main.swift in a multi-file build.
cp Sources/Preview.swift "$output/main.swift"
swiftc "${flags[@]}" -module-cache-path "$PWD/build/module-cache" -swift-version 5 -O \
  -framework AppKit Sources/Localization.swift Sources/Canvas.swift "$output/main.swift" -o "$output/NightShiftPreview"
swiftc "${flags[@]}" -module-cache-path "$PWD/build/module-cache" -swift-version 5 -O \
  -target arm64-apple-macosx15.0 Sources/WakeMonitor.swift -o "$output/NightShiftMonitor"
printf '%s\n' "$language" > "$output/language.txt"
printf 'Built %s edition in %s\n' "$language" "$output"
