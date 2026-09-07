#!/bin/bash
# Builds a universal release binary, wraps it in ClaudeUsageBar.app, ad-hoc
# signs it and zips it into dist/.
#
#   scripts/make-app.sh [version]
#
# The version defaults to the current git tag (leading "v" stripped), so a
# release is: tag, run this, upload the zip. Requires only the Xcode Command
# Line Tools. Resources/AppIcon.png comes from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=ClaudeUsageBar
BUNDLE_ID=com.jonathonlucas.ClaudeUsageBar
VERSION=${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}
VERSION=${VERSION:-0.0.0}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP=dist/$NAME.app
ZIP=dist/$NAME-$VERSION.zip

echo "Building $NAME $VERSION ($BUILD)"
swift build -c release --triple arm64-apple-macosx
swift build -c release --triple x86_64-apple-macosx

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  ".build/arm64-apple-macosx/release/$NAME" \
  ".build/x86_64-apple-macosx/release/$NAME" \
  -output "$APP/Contents/MacOS/$NAME"

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>      <string>en</string>
  <key>CFBundleExecutable</key>             <string>$NAME</string>
  <key>CFBundleIconFile</key>               <string>AppIcon</string>
  <key>CFBundleIdentifier</key>             <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>  <string>6.0</string>
  <key>CFBundleName</key>                   <string>$NAME</string>
  <key>CFBundlePackageType</key>            <string>APPL</string>
  <key>CFBundleShortVersionString</key>     <string>$VERSION</string>
  <key>CFBundleVersion</key>                <string>$BUILD</string>
  <key>LSApplicationCategoryType</key>      <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>         <string>13.0</string>
  <key>LSUIElement</key>                    <true/>
  <key>NSHighResolutionCapable</key>        <true/>
  <key>NSHumanReadableCopyright</key>       <string>© 2026 Jonathon Lucas. MIT License.</string>
  <key>NSPrincipalClass</key>               <string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: runs locally without a Developer ID. Downloads will
# still hit Gatekeeper once ("Open Anyway" in Privacy & Security).
codesign --force --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "Built $ZIP"
