#!/bin/bash
set -euo pipefail

PROJECT="Stag"
CONFIG="${1:-debug}"
ENTITLEMENTS="Stag.entitlements"
APP_BUNDLE="build/$PROJECT.app"

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)/"$PROJECT"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$PROJECT"
cp Sources/$PROJECT/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Sources/$PROJECT/Resources/Stag.icns "$APP_BUNDLE/Contents/Resources/"

# Apply hardened runtime + entitlements (required for screen recording)
if [ -f "$ENTITLEMENTS" ]; then
    # Try stable self-signed identity first (avoids re-granting permission on every build)
    if ! codesign --force --sign "Cropit Code Signing" \
        --entitlements "$ENTITLEMENTS" \
        --options runtime \
        "$APP_BUNDLE" 2>/dev/null; then
        # Fall back to ad-hoc
        codesign --force --sign - \
            --entitlements "$ENTITLEMENTS" \
            --options runtime \
            "$APP_BUNDLE"
    fi
fi

echo "✅ Built $APP_BUNDLE"
open "$APP_BUNDLE"
