#!/bin/bash
#
# Package a notarized .app into a signed, stapled DMG.
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="wishper-notary" \
#     script/dmg.sh path/to/Wishper.app path/to/output-dir
#
# Produces: <output-dir>/Wishper-<version>.dmg with Apple notarization
# stapled so users never see Gatekeeper warnings even offline.

set -euo pipefail

APP="${1:-}"
OUT_DIR="${2:-}"

if [ -z "$APP" ] || [ ! -d "$APP" ] || [ -z "$OUT_DIR" ]; then
    echo "usage: $0 path/to/Wishper.app path/to/output-dir" >&2
    exit 1
fi

: "${DEVELOPER_ID:?DEVELOPER_ID not set}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE not set}"

mkdir -p "$OUT_DIR"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")
DMG_NAME="Wishper-${VERSION}.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"
STAGING=$(mktemp -d -t wishper-dmg)
trap 'rm -rf "$STAGING"' EXIT

echo "[dmg] staging $APP"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "[dmg] creating $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Wishper" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    -fs HFS+ \
    "$DMG_PATH"

echo "[dmg] signing DMG"
codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

echo "[dmg] notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "[dmg] stapling"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "[dmg] ✓ $DMG_PATH"
