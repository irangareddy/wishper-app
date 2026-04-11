#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Wishper App"
SCHEME="Wishper App"
CONFIG="${1:-Release}"

echo "[wishper] Building ${CONFIG}..."
cd "$PROJECT_DIR"
xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" -destination "platform=macOS" build 2>&1 | tail -3

BUILD_DIR=$(xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | awk '{print $3}')

if [ ! -d "$BUILD_DIR/${APP_NAME}.app" ]; then
    echo "[wishper] Build failed — app not found"
    exit 1
fi

echo "[wishper] Installing to /Applications/..."
rm -rf "/Applications/${APP_NAME}.app"
cp -r "$BUILD_DIR/${APP_NAME}.app" "/Applications/${APP_NAME}.app"

echo "[wishper] Launching..."
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 1
open -a "/Applications/${APP_NAME}.app"

echo ""
echo "[wishper] Done!"
echo "  App: /Applications/${APP_NAME}.app"
echo "  Config: ${CONFIG}"
echo "  Size: $(du -sh "/Applications/${APP_NAME}.app" | cut -f1)"
