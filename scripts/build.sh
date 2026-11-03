#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_ARCH="${1:-universal}"
case "$BUILD_ARCH" in
  universal) ARCHITECTURES=(x86_64 arm64); ARCH_LABEL="Universal" ;;
  intel) ARCHITECTURES=(x86_64); ARCH_LABEL="Intel" ;;
  arm64) ARCHITECTURES=(arm64); ARCH_LABEL="AppleSilicon" ;;
  *) echo "Usage: $0 [universal|intel|arm64]" >&2; exit 2 ;;
esac
APP="$PWD/build/HotSpotAlive.app"
ICONSET="$PWD/build/HotSpotAlive.iconset"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET" "$PWD/build/bin"
xcrun swift scripts/make-icon.swift Resources/AppIconArtwork.png "$ICONSET"
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/HotSpotAlive.icns"
BINARIES=()
for architecture in "${ARCHITECTURES[@]}"; do
  binary="$PWD/build/bin/HotSpotAlive-$architecture"
  xcrun swiftc -swift-version 5 -O -whole-module-optimization \
    -target "$architecture-apple-macosx13.0" \
    Sources/HotSpotAlive/Core.swift Sources/HotSpotAlive/NetworkSupport.swift Sources/HotSpotAlive/main.swift \
    -o "$binary"
  BINARIES+=("$binary")
done
if [ "${#BINARIES[@]}" -gt 1 ]; then
  xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/HotSpotAlive"
else
  cp "${BINARIES[0]}" "$APP/Contents/MacOS/HotSpotAlive"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp README.md "$APP/Contents/Resources/README.md"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --strict "$APP"
ARCHIVE="$PWD/build/HotSpotAlive-$ARCH_LABEL.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
echo "Built: $APP"
xcrun lipo -archs "$APP/Contents/MacOS/HotSpotAlive"
/usr/bin/du -sh "$APP" "$ARCHIVE"
