#!/usr/bin/env bash
# Build SSM.app from the SwiftPM package. Usage: [VERSION=x.y.z] build-app.sh [--no-open]
# Command Line Tools are enough, no Xcode. The bundle is ad-hoc signed, not notarized.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$here/.build/SSM.app"
version="${VERSION:-0.0.0-dev}"

swift build -c release --package-path "$here" --product SsmApp
bin="$(swift build -c release --package-path "$here" --show-bin-path)/SsmApp"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/SSM"
# A committed .icns, since SwiftPM under Command Line Tools cannot build an asset catalog.
cp "$here/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleName</key><string>SSM</string>
    <key>CFBundleDisplayName</key><string>SSM</string>
    <key>CFBundleIdentifier</key><string>me.coilysiren.ssm</string>
    <key>CFBundleExecutable</key><string>SSM</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>CFBundleVersion</key><string>${version}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
  </dict>
</plist>
PLIST
codesign --force --sign - "$app"

echo "Built $app"
if [ "${1:-}" != "--no-open" ]; then
  open "$app"
fi
