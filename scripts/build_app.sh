#!/bin/bash
# Build a Apple Silicon macOS app with Command Line Tools; no external dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG="${1:-release}"
case "$CONFIG" in release|debug) ;; *) echo "Usage: $0 [release|debug]" >&2; exit 1 ;; esac
# Override SDKROOT when the active preview SDK requires unavailable SwiftUI plugins.
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
SDK_PATH="$(cd "$SDK_PATH" && pwd -P)"
# This preview CLT ships a SwiftUI State macro declaration without its plugin.
# Prefer its complete previous SDK when no SDK was explicitly requested.
if [ -z "${SDKROOT:-}" ] && [[ "$SDK_PATH" == */MacOSX27*.sdk ]] &&
   [ ! -f "$(xcode-select -p)/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ] &&
   [ -f "$(xcode-select -p)/SDKs/MacOSX26.5.sdk/SDKSettings.plist" ]; then
    SDK_PATH="$(xcode-select -p)/SDKs/MacOSX26.5.sdk"
fi
echo "Using SDK: $SDK_PATH"
APP="$ROOT/build/DropShelf.app"
mkdir -p "$ROOT/build"
swift build --build-system native --sdk "$SDK_PATH" --scratch-path .build/release-clean -c "$CONFIG" --arch arm64
# Assemble only after compilation succeeds.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARM_BIN="$(swift build --build-system native --sdk "$SDK_PATH" --scratch-path .build/release-clean -c "$CONFIG" --arch arm64 --show-bin-path)/DropShelf"
cp "$ARM_BIN" "$APP/Contents/MacOS/DropShelf"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Set SIGNING_IDENTITY to a Developer ID Application identity for public releases.
TIMESTAMP="--timestamp=none"
if [ -n "${SIGNING_IDENTITY:-}" ] && [ "$SIGNING_IDENTITY" != "-" ]; then
    TIMESTAMP="--timestamp"
fi
codesign --force --options runtime "$TIMESTAMP" --sign "${SIGNING_IDENTITY:--}" \
    --entitlements Resources/DropShelf.entitlements "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "Built: $APP"
# Explicit opt-in; building never changes the installed app by default.
if [ "${INSTALL:-0}" = "1" ]; then
    osascript -e 'tell application "DropShelf" to quit' 2>/dev/null || true
    for ((i=0; i<20; i++)); do
        if ! pgrep -x DropShelf >/dev/null; then break; fi
        sleep 0.25
    done
    if pgrep -x DropShelf >/dev/null; then
        echo "DropShelf is still running; quit it before installing." >&2
        exit 1
    fi
    DEST="/Applications/DropShelf.app"
    if [ -e "$DEST" ]; then
        ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")
        [ "$ID" = "com.dropshelf.app" ] || { echo "Unexpected app at $DEST" >&2; exit 1; }
    fi
    NEW="$(mktemp -d /Applications/.dropshelf-install.XXXXXX)"
    trap 'rm -rf "$NEW"' EXIT
    ditto "$APP" "$NEW/DropShelf.app"
    codesign --verify --strict "$NEW/DropShelf.app"
    rm -rf "$DEST"
    mv "$NEW/DropShelf.app" "$DEST"
    echo "Installed: $DEST"
fi
