#!/bin/bash
# Package the latest Apple Silicon app with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh release
mkdir -p dist
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/dropshelf-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
chmod 755 "$STAGE"
ditto build/DropShelf.app "$STAGE/DropShelf.app"
ln -s /Applications "$STAGE/Applications"
cp README.md "$STAGE/README.md"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
DMG="dist/DropShelf-$VERSION-arm64.dmg"
hdiutil create -volname DropShelf -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Created: $PWD/$DMG"
