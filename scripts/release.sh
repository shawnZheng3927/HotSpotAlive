#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Always package both native architectures for future Intel / Apple Silicon Macs.
./scripts/build.sh universal
xcrun lipo build/HotSpotAlive.app/Contents/MacOS/HotSpotAlive -verify_arch x86_64 arm64
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
RELEASE_DIR="$PWD/build/release"
BASE="HotSpotAlive-$VERSION"
mkdir -p "$RELEASE_DIR"
STAGING="$(mktemp -d "$PWD/build/dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

/usr/bin/ditto "$PWD/build/HotSpotAlive.app" "$STAGING/HotSpotAlive.app"
ln -s /Applications "$STAGING/Applications"
cp docs/INSTALL.zh-CN.txt "$STAGING/安装说明.txt"
/usr/bin/hdiutil create -ov -volname "HotSpotAlive $VERSION" -srcfolder "$STAGING" \
  -format UDZO -fs HFS+ "$RELEASE_DIR/$BASE-Universal.dmg"
cp build/HotSpotAlive-Universal.zip "$RELEASE_DIR/$BASE-Universal.zip"

# An explicit source allowlist keeps local build backups and personal files out of releases.
python3 - "$RELEASE_DIR/$BASE-Source.zip" <<'PY'
from pathlib import Path
import sys
import zipfile

roots = [Path(name) for name in (
    'Sources', 'Resources', 'Tests', 'scripts', 'docs', '.github',
    'README.md', '.gitignore', '.gitattributes', 'app logo.png', 'LICENSE',
)]
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for root in roots:
        if not root.exists():
            continue
        files = [root] if root.is_file() else sorted(root.rglob('*'))
        for item in files:
            if not item.is_file() or item.is_symlink():
                continue
            if item.name == '.DS_Store' or item.name.startswith('.env'):
                continue
            if item.suffix.lower() in ('.p12', '.p8', '.key', '.mobileprovision', '.pyc'):
                continue
            archive.write(item, Path('HotSpotAlive') / item)
PY

(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$BASE-Universal.dmg" "$BASE-Universal.zip" "$BASE-Source.zip" > "$BASE-SHA256SUMS.txt"
)
echo "Release files: $RELEASE_DIR"
/usr/bin/du -h "$RELEASE_DIR/$BASE-Universal.dmg" "$RELEASE_DIR/$BASE-Universal.zip" "$RELEASE_DIR/$BASE-Source.zip"
